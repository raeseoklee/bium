import Foundation
import BiumCore

enum Output {

    static func color(_ level: SafetyLevel, _ text: String) -> String {
        switch level {
        case .safe: return Ansi.green(text)
        case .review: return Ansi.yellow(text)
        case .caution: return Ansi.red(text)
        }
    }

    static func headline(_ level: SafetyLevel) -> String {
        switch level {
        case .safe: return t("safe · things the machine makes again", "안전 · 기기가 다시 만들어 주는 것")
        case .review: return t("worth a look · almost certainly disposable, but glance first", "확인 권장 · 거의 확실히 버려도 되지만 한번 보세요")
        case .caution: return t("careful · this may be real data", "주의 · 실제 데이터일 수 있습니다")
        }
    }

    static func printDisk(_ disk: DiskInfo) {
        let percent = Int((disk.usedFraction * 100).rounded())
        let bar = progressBar(fraction: disk.usedFraction, width: 24)
        print("""
        \(Ansi.bold(disk.volume))  \(bar) \(percent)% \(t("used", "사용"))
        \(Ansi.dim(t("Total", "전체"))) \(formatBytes(disk.totalBytes))   \
        \(Ansi.dim(t("Available", "사용 가능"))) \(formatBytes(disk.freeBytes))   \
        \(Ansi.dim(t("Reclaimable (incl. purgeable)", "확보 여지(purgeable 포함)"))) \(formatBytes(disk.importantAvailableBytes))
        """)
    }

    static func progressBar(fraction: Double, width: Int) -> String {
        let filled = max(0, min(width, Int((fraction * Double(width)).rounded())))
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
        if fraction >= 0.9 { return Ansi.red(bar) }
        if fraction >= 0.75 { return Ansi.yellow(bar) }
        return Ansi.green(bar)
    }

    // MARK: - Scan

    static func printScan(_ result: ScanResult, level: SafetyLevel, verbose: Bool) {
        printDisk(result.disk)

        let visible = result.groups.filter { $0.safety <= level && $0.bytes >= 0 }
        if visible.isEmpty {
            print("\n\(Ansi.green(t("Nothing to clean.", "정리할 것이 없습니다."))) \(t("No reclaimable space was found at this level.", "이 등급에서는 회수할 공간이 잡히지 않았습니다."))")
            printSkipped(result.skipped, verbose: verbose)
            return
        }

        let width = Ansi.width
        for safety in SafetyLevel.allCases where safety <= level {
            let groups = visible.filter { $0.safety == safety }
            guard !groups.isEmpty else { continue }
            let total = groups.reduce(Int64(0)) { $0 + $1.bytes }

            let title = " \(safety.label) — \(headline(safety)) "
            let suffix = " \(t("total", "합계")) \(formatBytes(total)) "
            let padding = max(3, width - title.count - suffix.count - 2)
            print("\n" + color(safety, "━━" + title + String(repeating: "━", count: padding)) + Ansi.bold(suffix))

            for group in groups.sorted(by: { $0.bytes > $1.bytes }) {
                let size = formatBytes(group.bytes).leftPadded(to: 9)
                let isAction = group.isAction
                let marker = isAction ? Ansi.cyan("▸") : " "
                print("  \(Ansi.bold(size)) \(marker) \(group.title)  \(Ansi.dim(group.ruleID))")

                if verbose {
                    print("      \(Ansi.dim(group.detail))")
                    for item in group.items.prefix(verbose ? 200 : 3) {
                        let itemSize = formatBytes(item.bytes).leftPadded(to: 9)
                        let path = item.kind == .action
                            ? "$ " + item.path
                            : Terminal.shorten(item.path, to: max(30, width - 24))
                        var line = "      \(Ansi.dim(itemSize))  \(path)"
                        if let note = item.note { line += Ansi.dim("  (\(note))") }
                        print(line)
                    }
                } else if let note = group.items.first?.note, group.items.count == 1 {
                    print("      \(Ansi.dim(note))")
                } else if group.isAction, let note = group.items.first?.note {
                    print("      \(Ansi.dim(note))")
                }
            }
        }

        printTotals(result, level: level)
        printSkipped(result.skipped, verbose: verbose)
    }

    private static func printTotals(_ result: ScanResult, level: SafetyLevel) {
        let parts = SafetyLevel.allCases
            .filter { $0 <= level }
            .map { "\(color($0, $0.label)) \(formatBytes(result.bytes(for: $0)))" }
        let total = result.groups.filter { $0.safety <= level }.reduce(Int64(0)) { $0 + $1.bytes }
        print("\n" + Ansi.bold(t("Total  ", "합계  ")) + parts.joined(separator: Ansi.dim("  ·  ")) + Ansi.dim("  =  ") + Ansi.bold(formatBytes(total)))

        let hasSnapshotAction = result.groups.contains { $0.ruleID == "action-tm-snapshots" }
        if hasSnapshotAction {
            print(Ansi.dim(t("      Time Machine local snapshots are excluded from the total: the amount is not known in advance.", "      Time Machine 로컬 스냅샷은 용량이 미리 계산되지 않아 합계에 빠져 있습니다.")))
        }
        print(Ansi.dim(t("\nNext:  bium clean --dry-run   →   bium clean", "\n다음 단계:  bium clean --dry-run   →   bium clean")))
    }

    private static func printSkipped(_ skipped: [SkippedRule], verbose: Bool) {
        guard !skipped.isEmpty else { return }
        // Always tell the user what was not looked at — a report that stays
        // silent about its gaps reads as full coverage.
        if verbose {
            print("\n" + Ansi.dim(t("\(skipped.count) rule(s) not scanned:", "검사하지 않은 규칙 \(skipped.count)개:")))
            for item in skipped {
                print(Ansi.dim("  \(item.ruleID.rightPadded(to: 26)) \(item.reason)"))
            }
        } else {
            print(Ansi.dim(t("\(skipped.count) rule(s) not scanned — use -v for details", "검사하지 않은 규칙 \(skipped.count)개 — 자세히 보려면 -v")))
        }
    }

    // MARK: - Clean

    static func printPlan(_ groups: [RuleGroup], mode: RemovalMode, dryRun: Bool, verbose: Bool) {
        let total = groups.reduce(Int64(0)) { $0 + $1.bytes }
        let action = dryRun
            ? t("preview", "미리보기")
            : (mode == .trash ? t("move to Trash", "휴지통으로 이동") : Ansi.red(t("delete immediately", "즉시 삭제")))
        print("\n\(Ansi.bold(t("Cleanup plan", "정리 계획"))) — \(action)")

        for group in groups.sorted(by: { $0.bytes > $1.bytes }) {
            let size = formatBytes(group.bytes).leftPadded(to: 9)
            print("  \(color(group.safety, group.safety.label.rightPadded(to: 8)))\(Ansi.bold(size))  \(group.title) \(Ansi.dim(t("(\(group.items.count) items)", "(\(group.items.count)개)")))")
            if verbose {
                for item in group.items {
                    let path = item.kind == .action ? "$ " + item.path : Terminal.shorten(item.path, to: max(30, Ansi.width - 20))
                    print("            \(Ansi.dim(path))")
                }
            }
        }
        print("  " + Ansi.bold(t("→ total \(formatBytes(total))", "→ 합계 \(formatBytes(total))")))
    }

    static func printReport(_ report: CleanReport, verbose: Bool) {
        let verb = report.dryRun
            ? t("Would have freed", "지웠을 용량")
            : (report.mode == .trash ? t("Moved to Trash", "휴지통으로 옮긴 용량") : t("Deleted", "삭제한 용량"))
        print("\n\(Ansi.bold(verb)): \(Ansi.green(formatBytes(report.reclaimedBytes)))")

        if !report.failures.isEmpty {
            print("\n\(Ansi.yellow(t("\(report.failures.count) item(s) skipped", "건너뛴 항목 \(report.failures.count)개")))")
            let shown = verbose ? report.failures : Array(report.failures.prefix(10))
            for failure in shown {
                print("  \(Ansi.dim(Terminal.shorten(failure.path, to: max(30, Ansi.width - 40))))")
                print("    \(Ansi.dim(failure.error ?? t("unknown reason", "알 수 없는 이유")))")
            }
            if shown.count < report.failures.count {
                print(Ansi.dim(t("  … and \(report.failures.count - shown.count) more (use -v for all)", "  … 외 \(report.failures.count - shown.count)개 (전부 보려면 -v)")))
            }
        }

        guard !report.dryRun else { return }

        if let after = report.diskAfter {
            let delta = after.freeBytes - report.diskBefore.freeBytes
            print("\n\(Ansi.dim(t("Available", "사용 가능 용량")))  \(formatBytes(report.diskBefore.freeBytes)) → \(Ansi.bold(formatBytes(after.freeBytes))) \(Ansi.dim("(\(delta >= 0 ? "+" : "")\(formatBytes(delta)))"))")
        }
        if report.mode == .trash {
            print(Ansi.yellow(t("\nThese were only moved to the Trash, so the space has not come back yet.", "\n휴지통으로 옮겼을 뿐이라 아직 실제 공간은 돌아오지 않았습니다.")))
            if case .accessDenied = Cleaner.trashState() {
                print(Cleaner.fullDiskAccessHint)
            } else {
                print(Ansi.dim(t("Check them, then empty it:  bium empty-trash", "확인 후 비우세요:  bium empty-trash")))
            }
        }
        print(Ansi.dim(t("Log: \(Cleaner.logDirectory)", "기록: \(Cleaner.logDirectory)")))
    }

    // MARK: - JSON

    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
    func rightPadded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
