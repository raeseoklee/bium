import Foundation

public struct Cleaner {
    public var mode: RemovalMode
    public var dryRun: Bool
    public var progress: (@Sendable (String) -> Void)?

    public init(
        mode: RemovalMode = .trash,
        dryRun: Bool = false,
        progress: (@Sendable (String) -> Void)? = nil
    ) {
        self.mode = mode
        self.dryRun = dryRun
        self.progress = progress
    }

    private var fm: FileManager { FileManager.default }

    public func clean(groups: [RuleGroup]) -> CleanReport {
        let startedAt = Date()
        let before = DiskInfo.current()
        var outcomes: [RemovalOutcome] = []

        for group in groups {
            for item in group.items {
                progress?(item.kind == .action
                    ? "\(t("Running", "실행")): \(group.title)"
                    : "\(t("Removing", "정리")): \(item.path)")
                outcomes.append(process(item, ruleTitle: group.title))
            }
        }

        let report = CleanReport(
            startedAt: startedAt,
            finishedAt: Date(),
            dryRun: dryRun,
            mode: mode,
            outcomes: outcomes,
            diskBefore: before,
            diskAfter: dryRun ? nil : DiskInfo.current()
        )
        if !dryRun { writeLog(report) }
        return report
    }

    private func process(_ item: CleanupItem, ruleTitle: String) -> RemovalOutcome {
        if item.kind == .action {
            return runAction(item)
        }

        // Re-validate immediately before removal rather than trusting the scan.
        // Between scan and clean a symlink could have been swapped, or the plan
        // could have been hand-edited via --include.
        do {
            try Guardrails.validate(item.path, root: item.root)
        } catch {
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: item.bytes,
                succeeded: false, mode: mode, error: "\(error)"
            )
        }

        guard fm.fileExists(atPath: item.path) || isDanglingSymlink(item.path) else {
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: 0,
                succeeded: false, mode: mode, error: t("already gone", "이미 없음")
            )
        }

        if dryRun {
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: item.bytes,
                succeeded: true, mode: mode, error: nil
            )
        }

        do {
            let url = URL(fileURLWithPath: item.path)
            switch mode {
            case .trash:
                try fm.trashItem(at: url, resultingItemURL: nil)
            case .permanent:
                try fm.removeItem(at: url)
            }
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: item.bytes,
                succeeded: true, mode: mode, error: nil
            )
        } catch {
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: item.bytes,
                succeeded: false, mode: mode,
                error: (error as NSError).localizedDescription
            )
        }
    }

    private func runAction(_ item: CleanupItem) -> RemovalOutcome {
        guard let command = item.command else {
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: 0,
                succeeded: false, mode: mode, error: t("no command to run", "실행할 명령이 없음")
            )
        }
        if dryRun {
            return RemovalOutcome(
                ruleID: item.ruleID, path: item.path, bytes: item.bytes,
                succeeded: true, mode: mode, error: nil
            )
        }
        // Actions delegate to first-party tools, so they can legitimately take
        // minutes (Docker image pruning, snapshot thinning).
        let result = Shell.run(command, timeout: 600)
        return RemovalOutcome(
            ruleID: item.ruleID, path: item.path, bytes: item.bytes,
            succeeded: result.succeeded, mode: mode,
            error: result.succeeded ? nil : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// `fileExists` follows symlinks, so a broken link reports as missing even
    /// though there is still a directory entry worth removing.
    private func isDanglingSymlink(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    // MARK: - Trash

    /// What we can tell about the Trash.
    ///
    /// macOS gates `~/.Trash` behind Full Disk Access, and a denied read looks
    /// exactly like an empty directory to `contentsOfDirectory`. Reporting that
    /// as "the Trash is empty" is worse than useless: it tells the user the
    /// space is gone when it is still occupied.
    public enum TrashState: Sendable {
        case empty
        case contents(PathSize)
        case accessDenied
    }

    public static func trashState() -> TrashState {
        let trash = "\(Guardrails.home)/.Trash"
        guard FileManager.default.fileExists(atPath: trash) else { return .empty }
        guard let names = readTrashEntries() else { return .accessDenied }
        guard !names.isEmpty else { return .empty }
        return .contents(SizeCalculator().size(of: trash))
    }

    /// Entry names in the Trash, or nil when the read was refused.
    static func readTrashEntries() -> [String]? {
        let trash = "\(Guardrails.home)/.Trash"
        guard let dir = opendir(trash) else {
            // EPERM here is the Full Disk Access gate, not a missing directory.
            return errno == EPERM || errno == EACCES ? nil : []
        }
        defer { closedir(dir) }

        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." || name == ".DS_Store" { continue }
            names.append(name)
        }
        return names
    }

    public enum EmptyTrashResult: Sendable {
        case done([RemovalOutcome])
        case accessDenied
    }

    /// Empties the Trash. Separate from `clean` because in `.trash` mode the
    /// space is not actually returned to the volume until this runs.
    public static func emptyTrash(dryRun: Bool) -> EmptyTrashResult {
        let fm = FileManager.default
        let trash = "\(Guardrails.home)/.Trash"
        guard let names = readTrashEntries() else { return .accessDenied }
        let sizer = SizeCalculator()
        let ledger = SizeCalculator.LinkLedger()

        return .done(names.map { name in
            let path = "\(trash)/\(name)"
            let bytes = sizer.size(of: path, ledger: ledger).bytes
            if dryRun {
                return RemovalOutcome(ruleID: "trash", path: path, bytes: bytes, succeeded: true, mode: .permanent, error: nil)
            }
            do {
                try Guardrails.validate(path, root: trash)
                try fm.removeItem(atPath: path)
                return RemovalOutcome(ruleID: "trash", path: path, bytes: bytes, succeeded: true, mode: .permanent, error: nil)
            } catch {
                return RemovalOutcome(
                    ruleID: "trash", path: path, bytes: bytes, succeeded: false,
                    mode: .permanent, error: "\(error)"
                )
            }
        })
    }

    /// Shown wherever the Trash turns out to be unreadable.
    public static var fullDiskAccessHint: String {
        t("""
        macOS is blocking reads of the Trash (Full Disk Access required).
        Either:
          · empty the Trash yourself in Finder, or
          · add your terminal under System Settings > Privacy & Security > Full Disk Access, then run this again.
        """, """
        macOS 가 휴지통 읽기를 막고 있습니다 (전체 디스크 접근 권한 필요).
        둘 중 하나로 해결하세요:
          · Finder 에서 휴지통을 직접 비우기
          · 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한 에 터미널 앱을 추가한 뒤 다시 실행
        """)
    }

    // MARK: - Logging

    public static var logDirectory: String {
        "\(Guardrails.home)/Library/Application Support/bium/logs"
    }

    /// Every real run leaves a record of what was removed, so a surprise later
    /// can be traced back to a specific rule.
    @discardableResult
    private func writeLog(_ report: CleanReport) -> String? {
        let dir = Cleaner.logDirectory
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withColonSeparatorInTime]
        let name = stamp.string(from: report.startedAt)
            .replacingOccurrences(of: ":", with: "")
        let path = "\(dir)/clean-\(name).json"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return nil }
        try? data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
