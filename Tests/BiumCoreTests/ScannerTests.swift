import Foundation
import BiumCore

func runScannerTests() throws {
    let scanner = CleanupScanner()

    // The regression that motivated the downward check: a broad SAFE sweep must
    // not re-offer a directory a narrower REVIEW rule already owns, or a
    // `--level safe` run silently deletes REVIEW-grade data.
    Check.suite("claiming/both directions") {
        let claimed: Set<String> = ["/a/b/cache/models/weights.bin"]
        Check.expect(scanner.isClaimed("/a/b/cache/models", claimed: claimed), "a directory whose descendant is claimed")
        Check.expect(scanner.isClaimed("/a/b/cache/models/weights.bin", claimed: claimed), "the exact same path")
        Check.expect(scanner.isClaimed("/a/b/cache/models/weights.bin/inner", claimed: claimed), "a path whose ancestor is claimed")
        Check.expect(!scanner.isClaimed("/a/b/cache/other", claimed: claimed), "an unrelated sibling is still offered")
    }

    Check.suite("claiming/path-aware, not string-prefix") {
        Check.expect(!scanner.isClaimed("/a/cache", claimed: ["/a/cache-old/x"]), "cache and cache-old are unrelated")
        Check.expect(!scanner.isClaimed("/a/cache-old", claimed: ["/a/cache"]), "cache-old and cache are unrelated")
    }

    Check.suite("age and extension filter") {
        let dir = try TempDir.make("age")
        try TempDir.write(16, to: "\(dir)/old-installer.dmg")
        try TempDir.write(16, to: "\(dir)/new-installer.dmg")
        try TempDir.write(16, to: "\(dir)/old-notes.txt")
        try TempDir.age("\(dir)/old-installer.dmg", days: 90)
        try TempDir.age("\(dir)/old-notes.txt", days: 90)

        let rule = Rule(
            id: "test", title: "t", detail: "d", category: .userFiles, safety: .review,
            target: .olderThan(dirs: [dir], days: 30, extensions: ["dmg"])
        )
        let names = Set(
            scanner.resolve(rule: rule, options: ScanOptions())
                .map { ($0.path as NSString).lastPathComponent }
        )
        Check.equal(names, ["old-installer.dmg"], "only old files with a matching extension")
    }

    // `build` and `dist` are common hand-made folder names, so a match only
    // counts when a sibling manifest shows something would rebuild it.
    Check.suite("project artifacts/require a sibling manifest") {
        let root = try TempDir.make("proj")
        try TempDir.write(16, to: "\(root)/real-project/package.json")
        try TempDir.write(16, to: "\(root)/real-project/dist/bundle.js")
        try TempDir.write(16, to: "\(root)/photos/dist/holiday.jpg")
        try TempDir.age("\(root)/real-project/dist", days: 365)
        try TempDir.age("\(root)/photos/dist", days: 365)

        let found = scanner.findArtifacts(
            under: root, names: ["dist"], cutoff: Date().addingTimeInterval(-60 * 86_400)
        )
        Check.equal(found.count, 1, "only the directory beside a manifest")
        Check.equal(found.first?.path ?? "", "\(root)/real-project/dist", "the photo folder's dist is left alone")
    }

    Check.suite("project artifacts/recently used is excluded") {
        let root = try TempDir.make("proj-recent")
        try TempDir.write(16, to: "\(root)/project/package.json")
        try TempDir.makeDirs(root, ["project/node_modules"])
        let found = scanner.findArtifacts(
            under: root, names: ["node_modules"], cutoff: Date().addingTimeInterval(-60 * 86_400)
        )
        Check.expect(found.isEmpty, "a recently used node_modules is not a candidate")
    }

    Check.suite("project artifacts/never descends into .git") {
        let root = try TempDir.make("proj-git")
        try TempDir.write(16, to: "\(root)/project/package.json")
        try TempDir.write(16, to: "\(root)/project/.git/modules/sub/dist/x.o")
        try TempDir.age("\(root)/project/.git/modules/sub/dist", days: 365)
        let found = scanner.findArtifacts(
            under: root, names: ["dist"], cutoff: Date().addingTimeInterval(-60 * 86_400)
        )
        Check.expect(found.isEmpty, ".git internals must not be walked")
    }

    // The bug this guards against: `clean --level safe` narrowed the scan to
    // SAFE rules, so the REVIEW rule that owns ~/.cache/huggingface never ran,
    // never claimed its path, and the broad SAFE sweep of ~/.cache picked up
    // ten gigabytes of model weights.
    Check.suite("claiming/an unselected rule still guards its paths") {
        let root = try TempDir.make("claim")
        try TempDir.write(4_000, to: "\(root)/models/weights.bin")
        try TempDir.write(4_000, to: "\(root)/ordinary/tmp.bin")

        let narrow = Rule(
            id: "narrow-review", title: "Models", detail: "d",
            category: .packageManager, safety: .review,
            target: .contentsOf(["\(root)/models"])
        )
        let broad = Rule(
            id: "broad-safe", title: "Broad sweep", detail: "d",
            category: .systemCache, safety: .safe,
            target: .contentsOf([root])
        )

        // Reporting only the broad SAFE rule, as `clean --level safe` does.
        let result = scanner.scan(
            rules: [narrow, broad],
            options: ScanOptions(includeActions: false, only: ["broad-safe"])
        )
        let offered = Set(result.groups.flatMap { $0.items }.map(\.path))

        Check.expect(
            !offered.contains("\(root)/models"),
            "a directory owned by a REVIEW rule must not join a SAFE sweep"
        )
        Check.expect(offered.contains("\(root)/ordinary"), "unrelated entries are still offered")
        Check.equal(result.groups.count, 1, "only the selected rule is reported")
    }

    Check.suite("claiming/an excluded rule still guards its paths") {
        let root = try TempDir.make("claim-exclude")
        try TempDir.write(4_000, to: "\(root)/models/weights.bin")

        let narrow = Rule(
            id: "narrow-review", title: "Models", detail: "d",
            category: .packageManager, safety: .review,
            target: .contentsOf(["\(root)/models"])
        )
        let broad = Rule(
            id: "broad-safe", title: "Broad sweep", detail: "d",
            category: .systemCache, safety: .safe,
            target: .contentsOf([root])
        )
        let result = scanner.scan(
            rules: [narrow, broad],
            options: ScanOptions(includeActions: false, exclude: ["narrow-review"])
        )
        let offered = Set(result.groups.flatMap { $0.items }.map(\.path))
        Check.expect(!offered.contains("\(root)/models"), "--exclude does not mean 'drop the protection'")
    }

    Check.suite("rule catalogue") {
        let ids = Rules.all().map(\.id)
        Check.equal(ids.count, Set(ids).count, "rule ids are unique")

        // Anything that can hold data the user cannot regenerate must not be SAFE.
        let mustNotBeSafe = [
            "ios-backups", "downloads-old", "downloads-installers", "trash",
            "xcode-archives", "simulator-devices", "huggingface-cache",
            "docker-disk-image", "maven-repo", "project-node-modules",
            "claude-vm-bundles", "jetbrains-old-versions",
        ]
        for id in mustNotBeSafe {
            guard let rule = Rules.rule(id: id) else {
                Check.expect(false, "rule \(id) is missing from the catalogue")
                continue
            }
            Check.expect(rule.safety != .safe, "\(id) must not be SAFE")
        }

        // Every rule must aim inside the home directory; the guardrails reject
        // anything else at delete time, so a rule pointing outside is a dead rule.
        for rule in Rules.all() {
            let paths: [String]
            switch rule.target {
            case .contentsOf(let p), .paths(let p), .orphanedEditorExtensions(let p):
                paths = p
            case .grandchildren(let roots, _), .olderThan(let roots, _, _),
                 .staleVersionedDirectories(let roots, _):
                paths = roots
            case .projectArtifacts, .action:
                continue
            }
            for path in paths {
                Check.expect(
                    path.hasPrefix(Guardrails.home + "/"),
                    "\(rule.id) points outside home: \(path)"
                )
            }
        }
    }
}
