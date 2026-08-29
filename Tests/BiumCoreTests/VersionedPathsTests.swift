import Foundation
import BiumCore

func runVersionedPathsTests() throws {

    Check.suite("extensions/only the registered ones survive") {
        let root = try TempDir.make("ext")
        try TempDir.makeDirs(root, [
            "anthropic.claude-code-1.0.0",
            "anthropic.claude-code-2.0.0",
            "dracula-theme.theme-dracula-2.25.1",
            ".0ab691bf-3a17-4540-86f2-816571539dab",
        ])
        let manifest = """
        [{"identifier":{"id":"anthropic.claude-code"},"version":"2.0.0","relativeLocation":"anthropic.claude-code-2.0.0"},
         {"identifier":{"id":"dracula-theme.theme-dracula"},"version":"2.25.1","relativeLocation":"dracula-theme.theme-dracula-2.25.1"}]
        """
        try manifest.write(toFile: "\(root)/extensions.json", atomically: true, encoding: .utf8)

        let names = Set(VersionedPaths.orphanedExtensions(in: root).map { ($0.path as NSString).lastPathComponent })
        Check.equal(
            names, ["anthropic.claude-code-1.0.0", ".0ab691bf-3a17-4540-86f2-816571539dab"],
            "only old versions and install debris become candidates"
        )
    }

    // Without a readable manifest we cannot tell live from dead, and guessing
    // wrong here uninstalls someone's working extensions.
    Check.suite("extensions/no manifest means no action") {
        let root = try TempDir.make("ext-none")
        try TempDir.makeDirs(root, ["some.extension-1.0.0"])
        Check.expect(VersionedPaths.orphanedExtensions(in: root).isEmpty, "manifest missing")

        let broken = try TempDir.make("ext-bad")
        try TempDir.makeDirs(broken, ["some.extension-1.0.0"])
        try "not json at all".write(toFile: "\(broken)/extensions.json", atomically: true, encoding: .utf8)
        Check.expect(VersionedPaths.orphanedExtensions(in: broken).isEmpty, "manifest corrupt")

        let empty = try TempDir.make("ext-empty")
        try TempDir.makeDirs(empty, ["some.extension-1.0.0"])
        try "[]".write(toFile: "\(empty)/extensions.json", atomically: true, encoding: .utf8)
        Check.expect(VersionedPaths.orphanedExtensions(in: empty).isEmpty, "manifest empty")
    }

    Check.suite("version parsing") {
        Check.equal(VersionedPaths.splitVersion("IntelliJIdea2024.2")?.version ?? [], [2024, 2], "IntelliJIdea2024.2")
        Check.equal(VersionedPaths.splitVersion("WebStorm2025.1.3")?.version ?? [], [2025, 1, 3], "WebStorm2025.1.3")
        Check.expect(VersionedPaths.splitVersion("consoleLog") == nil, "a name without a version yields nil")
    }

    Check.suite("versioned dirs/keep the newest") {
        let root = try TempDir.make("ver")
        try TempDir.makeDirs(root, [
            "IntelliJIdea2023.1", "IntelliJIdea2024.2", "IntelliJIdea2024.3", "IntelliJIdea2025.1",
            "WebStorm2024.1", "consoleLog",
        ])
        let stale = Set(
            VersionedPaths.supersededVersions(in: root, keepNewest: 2)
                .map { ($0.path as NSString).lastPathComponent }
        )
        Check.equal(stale, ["IntelliJIdea2023.1", "IntelliJIdea2024.2"], "everything except the two newest")
    }

    // A `-backup` directory is its own lineage; it must not be mistaken for a
    // superseded release of the product it was copied from.
    Check.suite("versioned dirs/suffixes are their own lineage") {
        let root = try TempDir.make("ver-suffix")
        try TempDir.makeDirs(root, ["IntelliJIdea2025.1", "IntelliJIdea2025.1-backup", "IntelliJIdea2024.1"])
        let stale = Set(
            VersionedPaths.supersededVersions(in: root, keepNewest: 1)
                .map { ($0.path as NSString).lastPathComponent }
        )
        Check.equal(stale, ["IntelliJIdea2024.1"], "-backup is not superseded by a newer release")
    }
}
