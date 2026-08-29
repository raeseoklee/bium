import Foundation

public struct ScanOptions: Sendable {
    /// Include the expensive walk of the user's source trees.
    public var deep: Bool
    /// Run `probe` commands for action rules. Disabled by `--no-actions`.
    public var includeActions: Bool
    /// Restrict to these rule ids, if non-empty.
    public var only: Set<String>
    /// Never report these rule ids.
    public var exclude: Set<String>
    /// Roots for the deep project walk. Defaults to the user's non-system home dirs.
    public var projectRoots: [String]?

    public init(
        deep: Bool = false,
        includeActions: Bool = true,
        only: Set<String> = [],
        exclude: Set<String> = [],
        projectRoots: [String]? = nil
    ) {
        self.deep = deep
        self.includeActions = includeActions
        self.only = only
        self.exclude = exclude
        self.projectRoots = projectRoots
    }
}

/// Resolves the rule catalogue against this machine and measures what it finds.
///
/// Named `CleanupScanner` rather than `Scanner` because Foundation already
/// exports a `Scanner`, and the two silently resolve in favour of Foundation's
/// at every call site that does not disambiguate.
public struct CleanupScanner {

    /// A resolved deletion candidate, before it has been sized.
    ///
    /// The resolution steps below are public because they are what the test
    /// runner and, later, the GUI need to inspect a rule without running a full
    /// scan — not because callers are expected to delete through them.
    public struct Candidate {
        public let path: String
        /// Directory the owning rule declared; the candidate must stay inside it.
        public let root: String
        public let note: String?
    }

    private let fm = FileManager.default
    private let sizer = SizeCalculator()
    public var progress: (@Sendable (String) -> Void)?

    public init(progress: (@Sendable (String) -> Void)? = nil) {
        self.progress = progress
    }

    public func scan(options: ScanOptions = ScanOptions()) -> ScanResult {
        scan(rules: Rules.all(), options: options)
    }

    /// Scans an explicit rule list. The catalogue overload is what callers want;
    /// this exists so the claiming behaviour can be tested against a synthetic
    /// rule set instead of whatever happens to be on the machine.
    public func scan(rules: [Rule], options: ScanOptions = ScanOptions()) -> ScanResult {
        var skipped: [SkippedRule] = []
        var groups: [RuleGroup] = []

        // Paths already owned by an earlier, more specific rule. Generic sweeps
        // consult this so nothing is counted — or deleted — twice.
        var claimed = Set<String>()
        var candidatesByRule: [(Rule, [Candidate])] = []

        for rule in rules {
            // Whether the caller asked to *report* this rule. Note that an
            // unselected rule still resolves below: its claims are what stop a
            // broad SAFE sweep from swallowing a narrow REVIEW directory. Filter
            // first and `clean --level safe` would happily delete model weights
            // out of ~/.cache because nothing had claimed them.
            let selected = (options.only.isEmpty || options.only.contains(rule.id))
                && !options.exclude.contains(rule.id)

            if rule.deep {
                // Deep rules cost a full tree walk and never overlap the cache
                // rules, so skipping them outright is safe as well as cheaper.
                if !options.deep {
                    if selected { skipped.append(SkippedRule(ruleID: rule.id, reason: t("not scanned without --deep", "--deep 없이는 검사하지 않음"))) }
                    continue
                }
                if !selected { continue }
            }

            // Actions run commands rather than claiming paths, so they are the
            // one kind we can skip entirely when unselected.
            if case .action(let spec) = rule.target {
                guard selected else { continue }
                guard options.includeActions else {
                    skipped.append(SkippedRule(ruleID: rule.id, reason: t("excluded by --no-actions", "--no-actions로 제외됨")))
                    continue
                }
                progress?("\(t("Scanning", "검사 중")): \(rule.title)")
                switch resolveAction(rule: rule, spec: spec) {
                case .success(let item):
                    groups.append(group(for: rule, items: [item]))
                case .failure(let reason):
                    skipped.append(SkippedRule(ruleID: rule.id, reason: reason))
                }
                continue
            }

            if selected { progress?("\(t("Scanning", "검사 중")): \(rule.title)") }

            // A directory macOS refuses to list looks identical to an empty one.
            // ~/.Trash is the common case: without Full Disk Access the rule
            // would quietly report nothing and the user would believe the space
            // had already been reclaimed.
            if selected {
                for root in unreadableRoots(of: rule) {
                    skipped.append(SkippedRule(
                        ruleID: rule.id,
                        reason: t("unreadable (needs Full Disk Access): \(root)", "읽을 수 없음(전체 디스크 접근 권한 필요): \(root)")
                    ))
                }
            }

            let candidates = resolve(rule: rule, options: options)
                .filter { !isClaimed($0.path, claimed: claimed) }
            for candidate in candidates { claimed.insert(candidate.path) }

            guard selected, !candidates.isEmpty else { continue }
            candidatesByRule.append((rule, candidates))
        }

        // One concurrent sizing pass over everything, sharing a ledger so a file
        // hard-linked into two candidates is only promised once.
        progress?(t("Measuring…", "용량 계산 중…"))
        let ledger = SizeCalculator.LinkLedger()
        let allPaths = candidatesByRule.flatMap { $0.1.map(\.path) }
        let sizes = sizer.sizes(of: allPaths, ledger: ledger)

        for (rule, candidates) in candidatesByRule {
            let items: [CleanupItem] = candidates.compactMap { candidate in
                let size = sizes[candidate.path] ?? .zero
                guard size.bytes > 0 || size.fileCount > 0 else { return nil }
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: candidate.path, isDirectory: &isDir)
                return CleanupItem(
                    ruleID: rule.id,
                    path: candidate.path,
                    root: candidate.root,
                    kind: isDir.boolValue ? .directory : .file,
                    bytes: size.bytes,
                    fileCount: max(size.fileCount, 1),
                    modified: size.newestModification,
                    note: candidate.note
                )
            }
            .sorted { $0.bytes > $1.bytes }

            if !items.isEmpty {
                groups.append(group(for: rule, items: items))
            }
        }

        groups.sort {
            if $0.safety != $1.safety { return $0.safety < $1.safety }
            return $0.bytes > $1.bytes
        }

        return ScanResult(
            scannedAt: Date(),
            disk: DiskInfo.current(),
            groups: groups,
            skipped: skipped
        )
    }

    private func group(for rule: Rule, items: [CleanupItem]) -> RuleGroup {
        RuleGroup(
            ruleID: rule.id, title: rule.title, detail: rule.detail,
            category: rule.category, safety: rule.safety, items: items
        )
    }

    /// True when an earlier, more specific rule already owns this path — in
    /// either direction.
    ///
    /// The upward check stops a child being offered twice. The downward check
    /// is the one that actually matters for safety: `~/.cache` is a SAFE sweep
    /// and `~/.cache/huggingface` is a REVIEW rule, so offering the parent
    /// would quietly drag gigabytes of model weights into a `--level safe` run.
    public func isClaimed(_ path: String, claimed: Set<String>) -> Bool {
        if claimed.contains(path) { return true }

        var current = (path as NSString).deletingLastPathComponent
        while current.count > 1 {
            if claimed.contains(current) { return true }
            current = (current as NSString).deletingLastPathComponent
        }

        let prefix = path + "/"
        return claimed.contains { $0.hasPrefix(prefix) }
    }

    // MARK: - Candidate resolution

    public func resolve(rule: Rule, options: ScanOptions) -> [Candidate] {
        switch rule.target {
        case .contentsOf(let dirs):
            return dirs.flatMap { dir -> [Candidate] in
                guard isDirectory(dir) else { return [] }
                return children(of: dir).map { Candidate(path: $0, root: dir, note: nil) }
            }

        case .paths(let paths):
            return paths.compactMap { path in
                guard fm.fileExists(atPath: path) else { return nil }
                let root = (path as NSString).deletingLastPathComponent
                return Candidate(path: path, root: root, note: nil)
            }

        case .grandchildren(let roots, let names):
            return roots.flatMap { root -> [Candidate] in
                guard isDirectory(root) else { return [] }
                return children(of: root).flatMap { appDir -> [Candidate] in
                    names.compactMap { name in
                        let path = "\(appDir)/\(name)"
                        guard fm.fileExists(atPath: path) else { return nil }
                        return Candidate(path: path, root: root, note: nil)
                    }
                }
            }

        case .olderThan(let dirs, let days, let extensions):
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            return dirs.flatMap { dir -> [Candidate] in
                guard isDirectory(dir) else { return [] }
                return children(of: dir).compactMap { path in
                    if let extensions {
                        let ext = (path as NSString).pathExtension.lowercased()
                        guard extensions.contains(ext) else { return nil }
                    }
                    guard let modified = modificationDate(of: path), modified < cutoff else { return nil }
                    let age = Int(Date().timeIntervalSince(modified) / 86_400)
                    return Candidate(path: path, root: dir, note: t("modified \(age) days ago", "\(age)일 전 수정"))
                }
            }

        case .projectArtifacts(let names, let idleDays):
            let roots = options.projectRoots ?? defaultProjectRoots()
            let cutoff = Date().addingTimeInterval(-Double(idleDays) * 86_400)
            return roots.flatMap { root in
                findArtifacts(under: root, names: Set(names), cutoff: cutoff)
                    .map { Candidate(path: $0.path, root: root, note: $0.note) }
            }

        case .orphanedEditorExtensions(let roots):
            return roots.flatMap { root -> [Candidate] in
                guard isDirectory(root) else { return [] }
                return VersionedPaths.orphanedExtensions(in: root)
                    .map { Candidate(path: $0.path, root: root, note: $0.note) }
            }

        case .staleVersionedDirectories(let roots, let keepNewest):
            return roots.flatMap { root -> [Candidate] in
                guard isDirectory(root) else { return [] }
                return VersionedPaths.supersededVersions(in: root, keepNewest: keepNewest)
                    .map { Candidate(path: $0.path, root: root, note: $0.note) }
            }

        case .action:
            return []
        }
    }

    /// Directories a rule points at that exist but cannot be listed.
    func unreadableRoots(of rule: Rule) -> [String] {
        let roots: [String]
        switch rule.target {
        case .contentsOf(let dirs), .orphanedEditorExtensions(let dirs):
            roots = dirs
        case .grandchildren(let dirs, _), .olderThan(let dirs, _, _),
             .staleVersionedDirectories(let dirs, _):
            roots = dirs
        case .paths, .projectArtifacts, .action:
            return []
        }
        return roots.filter { isDirectory($0) && !isReadableDirectory($0) }
    }

    func isReadableDirectory(_ path: String) -> Bool {
        guard let dir = opendir(path) else { return false }
        closedir(dir)
        return true
    }

    // MARK: - Filesystem helpers

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func children(of dir: String) -> [String] {
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return names.map { "\(dir)/\($0)" }
    }

    private func modificationDate(of path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    /// Top-level home directories that plausibly hold source code. Library and
    /// the media folders are excluded so the deep walk stays bounded.
    func defaultProjectRoots() -> [String] {
        let skip: Set<String> = [
            "Library", "Applications", "Pictures", "Music", "Movies", "Public",
            ".Trash", "Desktop",
        ]
        guard let names = try? fm.contentsOfDirectory(atPath: Guardrails.home) else { return [] }
        return names
            .filter { !skip.contains($0) }
            // Hidden dotfiles at home level are configuration, not projects.
            .filter { !$0.hasPrefix(".") }
            .map { "\(Guardrails.home)/\($0)" }
            .filter { isDirectory($0) && !Guardrails.isMountPoint($0) }
    }

    public struct Artifact {
        public let path: String
        public let note: String
    }

    /// Walks `root` looking for build-output directories that have not been
    /// touched since `cutoff`. Matched directories are not descended into, and
    /// the walk stops at `maxDepth` so a deep monorepo cannot stall the scan.
    public func findArtifacts(under root: String, names: Set<String>, cutoff: Date, maxDepth: Int32 = 8) -> [Artifact] {
        var found: [Artifact] = []

        root.withCString { cRoot in
            var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cRoot), nil]
            defer { free(paths[0]) }
            guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
            defer { fts_close(stream) }

            while let entry = fts_read(stream) {
                guard Int32(entry.pointee.fts_info) == FTS_D else { continue }
                if entry.pointee.fts_level == 0 { continue }

                // fts_name is a flexible array member, awkward to read from Swift;
                // the full path is a plain pointer, so derive the leaf from it.
                let path = String(cString: entry.pointee.fts_path)
                let name = (path as NSString).lastPathComponent

                if entry.pointee.fts_level >= maxDepth {
                    fts_set(stream, entry, FTS_SKIP)
                    continue
                }
                // Never walk into a repository's own metadata, and leave other
                // dot-directories alone unless they are explicitly named.
                if name == ".git" || (name.hasPrefix(".") && !names.contains(name)) {
                    fts_set(stream, entry, FTS_SKIP)
                    continue
                }

                if names.contains(name) {
                    // Don't descend — the whole directory is the candidate.
                    fts_set(stream, entry, FTS_SKIP)
                    guard let sp = entry.pointee.fts_statp else { continue }
                    let modified = Date(timeIntervalSince1970: TimeInterval(sp.pointee.st_mtimespec.tv_sec))
                    guard modified < cutoff else { continue }
                    // A `build`/`dist`/`target` directory only counts as an artifact
                    // when it sits next to something that would rebuild it.
                    guard name == "node_modules" || hasBuildManifest(besides: path) else { continue }
                    let age = Int(Date().timeIntervalSince(modified) / 86_400)
                    found.append(Artifact(path: path, note: t("untouched for \(age) days", "\(age)일간 변경 없음")))
                }
            }
        }
        return found
    }

    /// Guards against deleting a hand-made folder that happens to be called
    /// "build" or "dist" by requiring a sibling project manifest.
    private func hasBuildManifest(besides path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        let manifests = [
            "package.json", "Cargo.toml", "go.mod", "Package.swift", "pom.xml",
            "build.gradle", "build.gradle.kts", "pyproject.toml", "Makefile",
            "CMakeLists.txt", "tsconfig.json", "next.config.js", "next.config.mjs",
        ]
        return manifests.contains { fm.fileExists(atPath: "\(parent)/\($0)") }
    }

    // MARK: - Actions

    enum ActionResolution {
        case success(CleanupItem)
        case failure(String)
    }

    func resolveAction(rule: Rule, spec: ActionSpec) -> ActionResolution {
        guard Shell.which(spec.requires) != nil else {
            return .failure(t("skipped: \(spec.requires) is not installed", "\(spec.requires) 명령이 없어 건너뜀"))
        }
        guard let probe = spec.probe else {
            return .success(CleanupItem(
                ruleID: rule.id, path: spec.execute.joined(separator: " "),
                kind: .action, bytes: 0, fileCount: 0, command: spec.execute
            ))
        }

        let result = Shell.run(probe, timeout: 25)
        guard result.succeeded else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(t("probe failed (\(result.exitCode))", "점검 명령 실패 (\(result.exitCode))") + (detail.isEmpty ? "" : ": \(detail)"))
        }

        let estimate = ActionEstimator.estimate(spec.estimator, output: result.stdout)
        guard estimate.applicable else {
            return .failure(estimate.note ?? t("nothing to clean", "정리할 것이 없음"))
        }

        return .success(CleanupItem(
            ruleID: rule.id,
            path: spec.execute.joined(separator: " "),
            kind: .action,
            bytes: estimate.bytes,
            fileCount: 0,
            note: estimate.note,
            command: spec.execute
        ))
    }
}
