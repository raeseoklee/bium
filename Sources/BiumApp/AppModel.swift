import AppKit
import Foundation
import Observation
import BiumCore

enum Screen: String, CaseIterable, Identifiable {
    case scan, doctor, rules, history
    var id: String { rawValue }
}

/// Everything the window shows, and the only place that talks to BiumCore.
///
/// Scanning and cleaning both walk the filesystem, so they run off the main
/// actor and publish back; the views never block on them.
@Observable
@MainActor
final class AppModel {
    var screen: Screen = .scan
    var result: ScanResult?
    var report: CleanReport?
    var progress: String?
    var isBusy = false
    var deepScan = false
    var permanentDelete = false
    var confirming = false
    var error: String?

    /// Rule ids the user has ticked. SAFE rules are selected as they arrive;
    /// anything above SAFE has to be chosen deliberately, which mirrors the
    /// CLI defaulting to `--level safe`.
    var selected: Set<String> = []
    var expanded: Set<SafetyLevel> = [.safe]

    let strings = Strings()
    var disk: DiskInfo = .current()

    var groups: [RuleGroup] { result?.groups ?? [] }
    var skipped: [SkippedRule] { result?.skipped ?? [] }

    func groups(at level: SafetyLevel) -> [RuleGroup] {
        groups.filter { $0.safety == level }.sorted { $0.bytes > $1.bytes }
    }

    var selectedGroups: [RuleGroup] { groups.filter { selected.contains($0.ruleID) } }
    var selectedBytes: Int64 { selectedGroups.reduce(0) { $0 + $1.bytes } }
    var selectedItemCount: Int { selectedGroups.reduce(0) { $0 + $1.items.count } }

    /// True when the pending selection reaches past SAFE, which the footer
    /// warns about before anything is removed.
    var selectionExceedsSafe: Bool { selectedGroups.contains { $0.safety > .safe } }

    var unreadable: [SkippedRule] {
        skipped.filter { $0.reason.contains("Full Disk Access") || $0.reason.contains("전체 디스크 접근") }
    }

    // MARK: - Actions

    func scan() async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        report = nil
        let options = ScanOptions(deep: deepScan)

        // Progress arrives through a stream rather than a closure that captures
        // self, so nothing from the main actor crosses into the detached task.
        let (messages, publish) = AsyncStream<String>.makeStream()
        let work = Task.detached(priority: .userInitiated) {
            let scanner = CleanupScanner { publish.yield($0) }
            defer { publish.finish() }
            return scanner.scan(options: options)
        }
        for await message in messages { progress = message }
        let fresh = await work.value

        result = fresh
        disk = fresh.disk
        // Re-select SAFE only; a rescan must not silently carry a REVIEW or
        // CAUTION tick over to a set of groups the user has not looked at yet.
        selected = Set(fresh.groups.filter { $0.safety == .safe }.map(\.ruleID))
        progress = nil
        isBusy = false
    }

    func clean() async {
        guard !isBusy, !selectedGroups.isEmpty else { return }
        isBusy = true
        confirming = false
        let groups = selectedGroups
        let mode: RemovalMode = permanentDelete ? .permanent : .trash

        let (messages, publish) = AsyncStream<String>.makeStream()
        let work = Task.detached(priority: .userInitiated) {
            let cleaner = Cleaner(mode: mode, dryRun: false) { publish.yield($0) }
            defer { publish.finish() }
            return cleaner.clean(groups: groups)
        }
        for await message in messages { progress = message }
        let finished = await work.value

        report = finished
        progress = nil
        isBusy = false
        await scan()
    }

    func emptyTrash() async {
        guard !isBusy else { return }
        isBusy = true
        let outcome = await Task.detached(priority: .userInitiated) {
            Cleaner.emptyTrash(dryRun: false)
        }.value
        if case .accessDenied = outcome {
            error = Cleaner.fullDiskAccessHint
        }
        isBusy = false
        await scan()
    }

    func toggle(_ group: RuleGroup) {
        if selected.contains(group.ruleID) { selected.remove(group.ruleID) }
        else { selected.insert(group.ruleID) }
    }

    func toggleAll(at level: SafetyLevel) {
        let ids = groups(at: level).map(\.ruleID)
        if ids.allSatisfy(selected.contains) { ids.forEach { selected.remove($0) } }
        else { ids.forEach { selected.insert($0) } }
    }

    func openFullDiskAccess() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
