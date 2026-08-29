import Foundation

/// Reasons a path is refused. Every refusal is reported, never swallowed —
/// a silently skipped delete looks identical to a successful one otherwise.
public enum GuardrailError: Error, CustomStringConvertible, Sendable {
    case notAbsolute(String)
    case traversal(String)
    case protectedPath(String)
    case tooShallow(String)
    case outsideHome(String)
    case escapesRoot(path: String, root: String)
    case isMountPoint(String)

    public var description: String {
        switch self {
        case .notAbsolute(let p): return t("not an absolute path: \(p)", "절대 경로가 아님: \(p)")
        case .traversal(let p): return t("path contains '..': \(p)", "경로에 '..' 포함: \(p)")
        case .protectedPath(let p): return t("protected path, will not delete: \(p)", "보호된 경로라 삭제할 수 없음: \(p)")
        case .tooShallow(let p): return t("too close to the top level to delete: \(p)", "최상위에 너무 가까워 삭제할 수 없음: \(p)")
        case .outsideHome(let p): return t("outside the home directory, will not delete: \(p)", "홈 디렉터리 밖이라 삭제하지 않음: \(p)")
        case .escapesRoot(let path, let root): return t("escapes the rule root (\(root)): \(path)", "규칙 범위(\(root))를 벗어남: \(path)")
        case .isMountPoint(let p): return t("mount point, will not delete: \(p)", "마운트 지점이라 삭제하지 않음: \(p)")
        }
    }
}

/// The last line of defence before anything is removed.
///
/// Every candidate passes through `validate` immediately before deletion, not
/// just when it is produced during the scan. A rule bug, a symlink swapped
/// between scan and clean, or a hand-typed `--include` all get caught here.
public enum Guardrails {

    public static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    /// Paths that must never be removed even if a rule names them directly.
    /// These are containers we may delete *inside* of, never the thing itself.
    public static func protectedPaths() -> Set<String> {
        let h = home
        var set: Set<String> = [
            "/", "/Users", "/System", "/Library", "/Applications", "/bin", "/sbin",
            "/usr", "/usr/bin", "/usr/local", "/etc", "/var", "/private", "/opt",
            "/opt/homebrew", "/Volumes", "/cores", "/dev", "/tmp",
        ]
        for name in [
            "", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies",
            "Music", "Public", "Applications", "Library/Application Support",
            "Library/Containers", "Library/Group Containers", "Library/Preferences",
            "Library/Keychains", "Library/Mobile Documents", "Library/Developer",
            "Library/Caches", "Library/Logs", "Library/Safari", "Library/Mail",
            "Library/Messages", "Library/Photos", "Library/CloudStorage",
            ".ssh", ".gnupg", ".config", ".local", ".Trash",
        ] {
            set.insert(name.isEmpty ? h : "\(h)/\(name)")
        }
        return set
    }

    /// Directory names that must never be removed wholesale wherever they appear.
    /// `.git` is the one that actually bites people: a stray rule matching a
    /// project directory would take the history with it.
    public static let protectedNames: Set<String> = [
        ".git", ".hg", ".svn", "node_modules_DO_NOT", "Keychains", "Mobile Documents",
    ]

    /// Validates a path for deletion.
    ///
    /// - Parameters:
    ///   - path: candidate path, as produced by a rule.
    ///   - root: the directory the owning rule declared. The candidate must
    ///           stay inside it even after symlinks are resolved.
    public static func validate(_ path: String, root: String?) throws {
        let std = (path as NSString).standardizingPath

        guard std.hasPrefix("/") else { throw GuardrailError.notAbsolute(path) }
        guard !std.contains("/../"), !std.hasSuffix("/..") else { throw GuardrailError.traversal(path) }

        let components = std.split(separator: "/").map(String.init)
        // "/Users/you/x" is three components — the shallowest we ever accept.
        guard components.count >= 3 else { throw GuardrailError.tooShallow(std) }

        if protectedPaths().contains(std) { throw GuardrailError.protectedPath(std) }
        if let last = components.last, protectedNames.contains(last) {
            throw GuardrailError.protectedPath(std)
        }

        // Everything this tool touches lives under the user's home. System-wide
        // caches need root and are deliberately out of scope.
        guard std == home || std.hasPrefix(home + "/") else { throw GuardrailError.outsideHome(std) }

        if let root {
            let stdRoot = (root as NSString).standardizingPath
            guard std.hasPrefix(stdRoot + "/") else {
                throw GuardrailError.escapesRoot(path: std, root: stdRoot)
            }
            // Resolve symlinks on both sides and re-check. A symlink placed
            // inside a cache directory must not become a handle on the rest of
            // the filesystem. We only resolve the *parent*, because the leaf
            // may legitimately be a symlink we want to unlink in place.
            let parent = (std as NSString).deletingLastPathComponent
            let realParent = URL(fileURLWithPath: parent).resolvingSymlinksInPath().path
            let realRoot = URL(fileURLWithPath: stdRoot).resolvingSymlinksInPath().path
            guard realParent == realRoot || realParent.hasPrefix(realRoot + "/") else {
                throw GuardrailError.escapesRoot(path: std, root: stdRoot)
            }
        }

        if isMountPoint(std) { throw GuardrailError.isMountPoint(std) }
    }

    /// True when `path` is the root of its own filesystem — deleting into a
    /// mounted volume (an external disk, a network share) is never intended.
    public static func isMountPoint(_ path: String) -> Bool {
        var selfStat = stat()
        var parentStat = stat()
        guard lstat(path, &selfStat) == 0 else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard lstat(parent, &parentStat) == 0 else { return false }
        return selfStat.st_dev != parentStat.st_dev
    }
}
