import Foundation

// MARK: - Safety

/// How risky it is to remove a candidate.
///
/// The whole point of this tool is that the default path only ever touches
/// `.safe`: things the machine regenerates on its own. Anything that could
/// hold work the user cannot get back lives in `.review` or `.caution` and
/// never moves without an explicit opt-in.
public enum SafetyLevel: String, Sendable, Codable, CaseIterable {
    /// Regenerated automatically. Deleting costs time, never data.
    case safe
    /// Almost certainly disposable, but the contents are user-specific.
    case review
    /// Real user data or expensive-to-rebuild state. Opt in per rule.
    case caution

    public var rank: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .caution: return 2
        }
    }

    public var label: String { rawValue.uppercased() }

    public var localized: String {
        switch self {
        case .safe: return t("safe", "안전")
        case .review: return t("worth a look", "확인 권장")
        case .caution: return t("careful", "주의")
        }
    }
}

extension SafetyLevel: Comparable {
    public static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Category

public enum Category: String, Sendable, Codable, CaseIterable {
    case xcode
    case packageManager
    case apps
    case browsers
    case systemCache
    case logs
    case userFiles
    case containers
    case projects

    public var localized: String {
        switch self {
        case .xcode: return t("Xcode & simulators", "Xcode / 시뮬레이터")
        case .packageManager: return t("Package manager caches", "패키지 매니저 캐시")
        case .apps: return t("Applications", "애플리케이션")
        case .browsers: return t("Browsers", "브라우저")
        case .systemCache: return t("System caches", "시스템 캐시")
        case .logs: return t("Logs", "로그")
        case .userFiles: return t("User files", "사용자 파일")
        case .containers: return t("Containers & VMs", "컨테이너 / 가상화")
        case .projects: return t("Project build output", "프로젝트 빌드 산출물")
        }
    }
}

// MARK: - Rules

/// Where a rule's candidates come from.
public enum RuleTarget: Sendable {
    /// Delete every child of these directories, keeping the directories themselves.
    /// Used for caches whose parent directory an app expects to exist.
    case contentsOf([String])

    /// Delete these paths outright.
    case paths([String])

    /// For each `root`, for each child `C` of `root`, offer `root/C/<name>`.
    /// This is how the generic Electron-app cache sweep works
    /// (`~/Library/Application Support/*/Code Cache`).
    case grandchildren(of: [String], named: [String])

    /// Direct entries of `dirs` whose modification date is older than `days`.
    /// `extensions` narrows it to e.g. installer images only.
    case olderThan(dirs: [String], days: Int, extensions: [String]?)

    /// Build artifacts found by walking the user's source trees.
    /// Only offered under `--deep` because the walk is expensive.
    case projectArtifacts(names: [String], idleDays: Int)

    /// Extension directories an editor no longer references.
    /// Each root is a VS Code-style `extensions` folder whose `extensions.json`
    /// is the authoritative list of what is actually installed; everything else
    /// in the folder is a leftover from an update or an interrupted install.
    case orphanedEditorExtensions([String])

    /// Per-version directories where only the newest few still matter,
    /// e.g. `~/Library/Application Support/JetBrains/IntelliJIdea2024.2`.
    case staleVersionedDirectories(roots: [String], keepNewest: Int)

    /// Not a file deletion — a command that reclaims space on our behalf.
    case action(ActionSpec)
}

/// A reclaim step delegated to a first-party tool because doing it by hand
/// would be less safe than letting the tool do it (APFS snapshots, simulators,
/// Docker's disk image).
public struct ActionSpec: Sendable {
    /// Executable that must exist for the action to be offered at all.
    public let requires: String
    /// Command run during `scan` to estimate what the action would free.
    public let probe: [String]?
    /// How to turn `probe` output into a byte estimate.
    public let estimator: Estimator
    /// Command run during `clean`.
    public let execute: [String]

    public enum Estimator: String, Sendable {
        case none
        case brewCleanupDryRun
        case dockerSystemDF
        case timeMachineSnapshots
        case simctlUnavailable
    }

    public init(
        requires: String,
        probe: [String]?,
        estimator: Estimator,
        execute: [String]
    ) {
        self.requires = requires
        self.probe = probe
        self.estimator = estimator
        self.execute = execute
    }
}

public struct Rule: Sendable {
    public let id: String
    /// Short human name, shown as the group header.
    public let title: String
    /// What the thing actually is, and what it costs to delete it.
    public let detail: String
    public let category: Category
    public let safety: SafetyLevel
    public let target: RuleTarget
    /// Only surfaced when the user passes `--deep`.
    public let deep: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        category: Category,
        safety: SafetyLevel,
        target: RuleTarget,
        deep: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.safety = safety
        self.target = target
        self.deep = deep
    }
}

// MARK: - Scan output

public enum ItemKind: String, Sendable, Codable {
    case file
    case directory
    case action
}

public struct CleanupItem: Sendable, Codable {
    public let ruleID: String
    /// Absolute path, or a human description of the command for `.action` items.
    public let path: String
    /// Directory the owning rule declared. Re-checked at deletion time so a
    /// stale or hand-edited plan cannot reach outside the rule's scope.
    public let root: String?
    public let kind: ItemKind
    /// On-disk allocated bytes. For actions this is an estimate and may be 0
    /// when the tool cannot tell us in advance.
    public let bytes: Int64
    public let fileCount: Int
    /// Most recent modification found underneath, when known.
    public let modified: Date?
    /// Per-item caveat, e.g. "mostly hard links, so the real saving is smaller".
    public let note: String?
    /// Present only for `.action` items.
    public let command: [String]?

    public init(
        ruleID: String,
        path: String,
        root: String? = nil,
        kind: ItemKind,
        bytes: Int64,
        fileCount: Int,
        modified: Date? = nil,
        note: String? = nil,
        command: [String]? = nil
    ) {
        self.ruleID = ruleID
        self.path = path
        self.root = root
        self.kind = kind
        self.bytes = bytes
        self.fileCount = fileCount
        self.modified = modified
        self.note = note
        self.command = command
    }
}

public struct RuleGroup: Sendable, Codable {
    public let ruleID: String
    public let title: String
    public let detail: String
    public let category: Category
    public let safety: SafetyLevel
    public let items: [CleanupItem]

    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var fileCount: Int { items.reduce(0) { $0 + $1.fileCount } }
    public var isAction: Bool { items.contains { $0.kind == .action } }

    public init(
        ruleID: String,
        title: String,
        detail: String,
        category: Category,
        safety: SafetyLevel,
        items: [CleanupItem]
    ) {
        self.ruleID = ruleID
        self.title = title
        self.detail = detail
        self.category = category
        self.safety = safety
        self.items = items
    }
}

public struct ScanResult: Sendable, Codable {
    public let scannedAt: Date
    public let disk: DiskInfo
    public let groups: [RuleGroup]
    /// Rules that were skipped and why — kept so the report never silently
    /// implies coverage it does not have.
    public let skipped: [SkippedRule]

    public var totalBytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }

    public func groups(upTo level: SafetyLevel) -> [RuleGroup] {
        groups.filter { $0.safety <= level }
    }

    public func bytes(for level: SafetyLevel) -> Int64 {
        groups.filter { $0.safety == level }.reduce(0) { $0 + $1.bytes }
    }

    public init(scannedAt: Date, disk: DiskInfo, groups: [RuleGroup], skipped: [SkippedRule]) {
        self.scannedAt = scannedAt
        self.disk = disk
        self.groups = groups
        self.skipped = skipped
    }
}

public struct SkippedRule: Sendable, Codable {
    public let ruleID: String
    public let reason: String

    public init(ruleID: String, reason: String) {
        self.ruleID = ruleID
        self.reason = reason
    }
}

// MARK: - Clean output

public enum RemovalMode: String, Sendable, Codable {
    /// `FileManager.trashItem` — recoverable, but space is only reclaimed
    /// once the Trash is emptied.
    case trash
    /// `FileManager.removeItem` — immediate, irreversible.
    case permanent
}

public struct RemovalOutcome: Sendable, Codable {
    public let ruleID: String
    public let path: String
    public let bytes: Int64
    public let succeeded: Bool
    public let mode: RemovalMode
    public let error: String?

    public init(ruleID: String, path: String, bytes: Int64, succeeded: Bool, mode: RemovalMode, error: String?) {
        self.ruleID = ruleID
        self.path = path
        self.bytes = bytes
        self.succeeded = succeeded
        self.mode = mode
        self.error = error
    }
}

public struct CleanReport: Sendable, Codable {
    public let startedAt: Date
    public let finishedAt: Date
    public let dryRun: Bool
    public let mode: RemovalMode
    public let outcomes: [RemovalOutcome]
    public let diskBefore: DiskInfo
    public let diskAfter: DiskInfo?

    public var reclaimedBytes: Int64 {
        outcomes.filter(\.succeeded).reduce(0) { $0 + $1.bytes }
    }
    public var failures: [RemovalOutcome] { outcomes.filter { !$0.succeeded } }

    public init(
        startedAt: Date,
        finishedAt: Date,
        dryRun: Bool,
        mode: RemovalMode,
        outcomes: [RemovalOutcome],
        diskBefore: DiskInfo,
        diskAfter: DiskInfo?
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.dryRun = dryRun
        self.mode = mode
        self.outcomes = outcomes
        self.diskBefore = diskBefore
        self.diskAfter = diskAfter
    }
}

// MARK: - Formatting

public func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    // .file matches what Finder reports, which is what the user is comparing against.
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.zeroPadsFractionDigits = false
    return formatter.string(fromByteCount: bytes)
}
