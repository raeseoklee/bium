import Foundation

/// Helpers for the two "old copies pile up" shapes that dominate a developer
/// machine: editor extension folders and per-release application-support
/// directories. Both are large, both are invisible in Finder, and both are only
/// safe to touch if you can tell which copy is still live.
public enum VersionedPaths {

    // MARK: - Editor extensions

    public struct Orphan {
        public let path: String
        public let note: String
    }

    /// Directories inside a VS Code-style `extensions` folder that the editor
    /// no longer references.
    ///
    /// `extensions.json` is the editor's own record of what is installed, so it
    /// — not a version-number heuristic — decides what stays. If that file is
    /// missing or unreadable we return nothing rather than guess, because
    /// guessing wrong here uninstalls someone's extensions.
    public static func orphanedExtensions(in root: String) -> [Orphan] {
        let fm = FileManager.default
        let manifest = "\(root)/extensions.json"
        guard
            let data = fm.contents(atPath: manifest),
            let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            !entries.isEmpty
        else { return [] }

        var live = Set<String>()
        for entry in entries {
            if let location = entry["relativeLocation"] as? String {
                live.insert(location)
            }
            // Older manifests store an absolute location instead.
            if let location = entry["location"] as? [String: Any],
               let path = location["path"] as? String {
                live.insert((path as NSString).lastPathComponent)
            }
        }
        guard !live.isEmpty else { return [] }

        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        return names.compactMap { name in
            guard !live.contains(name) else { return nil }
            let path = "\(root)/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            // Interrupted installs leave UUID-named staging folders behind.
            let note = name.hasPrefix(".")
                ? t("leftover from an interrupted install", "설치 중단 잔여물")
                : t("\(displayName(name)) — unregistered old version", "\(displayName(name)) — 등록되지 않은 옛 버전")
            return Orphan(path: path, note: note)
        }
    }

    /// `anthropic.claude-code-1.2.3` → `anthropic.claude-code 1.2.3`
    private static func displayName(_ directoryName: String) -> String {
        guard let range = directoryName.range(
            of: #"-\d+\.\d+\.\d+.*$"#,
            options: .regularExpression
        ) else { return directoryName }
        let id = String(directoryName[..<range.lowerBound])
        let version = String(directoryName[range.lowerBound...].dropFirst())
        return "\(id) \(version)"
    }

    // MARK: - Versioned application directories

    /// Directories in `root` that are superseded by a newer release of the same
    /// product. `keepNewest` most recent versions of each product are retained.
    ///
    /// Entries are grouped by everything that is not the version number, so
    /// `IntelliJIdea2025.1` and `IntelliJIdea2025.1-backup` are treated as
    /// different products and a backup is never mistaken for a live release.
    public static func supersededVersions(in root: String, keepNewest: Int) -> [Orphan] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }

        struct Entry {
            let name: String
            let version: [Int]
        }
        var groups: [String: [Entry]] = [:]

        for name in names where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: "\(root)/\(name)", isDirectory: &isDir), isDir.boolValue else { continue }
            guard let parsed = splitVersion(name) else { continue }
            groups[parsed.key, default: []].append(Entry(name: name, version: parsed.version))
        }

        var orphans: [Orphan] = []
        for (_, entries) in groups where entries.count > keepNewest {
            let sorted = entries.sorted { lhs, rhs in compare(lhs.version, rhs.version) == .orderedDescending }
            let newest = sorted.prefix(keepNewest).map(\.name).joined(separator: ", ")
            for entry in sorted.dropFirst(keepNewest) {
                orphans.append(Orphan(
                    path: "\(root)/\(entry.name)",
                    note: t("\(newest) is newer", "\(newest) 이(가) 최신")
                ))
            }
        }
        return orphans
    }

    /// Splits `IntelliJIdea2024.2` into key `IntelliJIdea` + version `[2024, 2]`.
    /// Returns nil when the name carries no version, since an unversioned
    /// directory has nothing to be superseded by.
    public static func splitVersion(_ name: String) -> (key: String, version: [Int])? {
        let pattern = #"^(.*?)((?:\d+\.)+\d+|\d{4}\.\d+)(.*)$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
            let prefixRange = Range(match.range(at: 1), in: name),
            let versionRange = Range(match.range(at: 2), in: name),
            let suffixRange = Range(match.range(at: 3), in: name)
        else { return nil }

        let version = name[versionRange].split(separator: ".").compactMap { Int($0) }
        guard !version.isEmpty else { return nil }
        return (key: "\(name[prefixRange])|\(name[suffixRange])", version: version)
    }

    public static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
