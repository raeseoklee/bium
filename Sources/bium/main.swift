import Foundation
import BiumCore

func run() -> Int32 {
    let options: Options
    do {
        options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        Terminal.error("\(error)")
        print(Ansi.dim(t("\nHelp: bium --help", "\n도움말: bium --help")))
        return 64
    }

    switch options.command {
    case .help:
        print(helpText)
        return 0
    case .list:
        listRules()
        return 0
    case .doctor:
        doctor()
        return 0
    case .scan:
        return runScan(options)
    case .clean:
        return runClean(options)
    case .emptyTrash:
        return runEmptyTrash(options)
    }
}

// MARK: - scan

func runScan(_ options: Options) -> Int32 {
    let scanner = CleanupScanner(progress: { message in Terminal.status(message) })
    let result = scanner.scan(options: options.scanOptions)
    Terminal.clearStatus()

    if options.json {
        Output.printJSON(result)
    } else {
        Output.printScan(result, level: options.level, verbose: options.verbose)
    }
    return 0
}

// MARK: - clean

func runClean(_ options: Options) -> Int32 {
    // Narrow the scan itself to the levels being cleaned so we never spend time
    // sizing directories we have already decided not to touch.
    var scanOptions = options.scanOptions
    let eligible = Set(Rules.all().filter { $0.safety <= options.level }.map(\.id))
    scanOptions.only = scanOptions.only.isEmpty ? eligible : scanOptions.only.intersection(eligible)

    if scanOptions.only.isEmpty {
        Terminal.error(t("The rules given with --only are outside --level \(options.level.rawValue).", "--only 로 지정한 규칙이 --level \(options.level.rawValue) 범위에 없습니다."))
        return 65
    }

    let scanner = CleanupScanner(progress: { message in Terminal.status(message) })
    let result = scanner.scan(options: scanOptions)
    Terminal.clearStatus()

    let groups = result.groups.filter { $0.safety <= options.level && !$0.items.isEmpty }
    guard !groups.isEmpty else {
        print("\(Ansi.green(t("Nothing to clean.", "정리할 것이 없습니다."))) \(t("No reclaimable space was found at this level.", "이 등급에서 회수할 공간이 잡히지 않았습니다."))")
        return 0
    }

    if !options.json {
        Output.printDisk(result.disk)
        Output.printPlan(groups, mode: options.permanent ? .permanent : .trash, dryRun: options.dryRun, verbose: options.verbose)

        if options.level > .safe && !options.levelWasExplicit {
            print(Ansi.yellow(t("\nThis includes items above the SAFE level.", "\nSAFE 등급을 넘어서는 항목이 포함되어 있습니다.")))
        }
        if options.permanent && !options.dryRun {
            print(Ansi.red(t("\n--permanent: the Trash is bypassed. This cannot be undone.", "\n--permanent: 휴지통을 거치지 않습니다. 되돌릴 수 없습니다.")))
        }
    }

    if !options.dryRun && !options.assumeYes {
        let question = options.permanent
            ? t("\(Ansi.red("Permanently delete")) the items above. Continue?", "위 항목을 \(Ansi.red("영구 삭제"))합니다. 계속할까요?")
            : t("Move the items above to the Trash. Continue?", "위 항목을 휴지통으로 옮깁니다. 계속할까요?")
        guard Terminal.confirm(question) else {
            print(Ansi.dim(t("Cancelled.", "취소했습니다.")))
            return 0
        }
    }

    let cleaner = Cleaner(
        mode: options.permanent ? .permanent : .trash,
        dryRun: options.dryRun,
        progress: { message in Terminal.status(message) }
    )
    let report = cleaner.clean(groups: groups)
    Terminal.clearStatus()

    if options.json {
        Output.printJSON(report)
    } else {
        Output.printReport(report, verbose: options.verbose)
    }
    return report.failures.isEmpty ? 0 : 1
}

// MARK: - empty-trash

func runEmptyTrash(_ options: Options) -> Int32 {
    let size: PathSize
    switch Cleaner.trashState() {
    case .empty:
        print("\(Ansi.green(t("The Trash is empty.", "휴지통이 비어 있습니다.")))")
        return 0
    case .accessDenied:
        Terminal.error(t("Cannot read the Trash.", "휴지통을 읽을 수 없습니다."))
        print(Cleaner.fullDiskAccessHint)
        return 77
    case .contents(let measured):
        size = measured
    }

    print("\(t("Trash", "휴지통")): \(Ansi.bold(formatBytes(size.bytes)))  \(Ansi.dim(t("\(size.fileCount) files", "파일 \(size.fileCount)개")))")
    print(Ansi.dim(t("Emptying it cannot be undone.", "비우면 되돌릴 수 없습니다.")))

    if !options.dryRun && !options.assumeYes {
        guard Terminal.confirm(t("Empty the Trash?", "휴지통을 비울까요?")) else {
            print(Ansi.dim(t("Cancelled.", "취소했습니다.")))
            return 0
        }
    }

    let before = DiskInfo.current()
    let outcomes: [RemovalOutcome]
    switch Cleaner.emptyTrash(dryRun: options.dryRun) {
    case .accessDenied:
        Terminal.error(t("Cannot read the Trash.", "휴지통을 읽을 수 없습니다."))
        print(Cleaner.fullDiskAccessHint)
        return 77
    case .done(let result):
        outcomes = result
    }
    let freed = outcomes.filter(\.succeeded).reduce(Int64(0)) { $0 + $1.bytes }
    let failures = outcomes.filter { !$0.succeeded }

    print("\n\(options.dryRun ? t("Would have emptied", "비웠을 용량") : t("Emptied", "비운 용량")): \(Ansi.green(formatBytes(freed)))")
    for failure in failures {
        print("  \(Ansi.yellow(t("skipped", "건너뜀"))) \(Terminal.shorten(failure.path, to: 60)) — \(Ansi.dim(failure.error ?? ""))")
    }
    if !options.dryRun {
        let after = DiskInfo.current()
        print("\(Ansi.dim(t("Available", "사용 가능 용량")))  \(formatBytes(before.freeBytes)) → \(Ansi.bold(formatBytes(after.freeBytes)))")
    }
    return failures.isEmpty ? 0 : 1
}

// MARK: - list

func listRules() {
    let width = Ansi.width
    for safety in SafetyLevel.allCases {
        let rules = Rules.all().filter { $0.safety == safety }
        guard !rules.isEmpty else { continue }
        print("\n" + Output.color(safety, Ansi.bold("\(safety.label) — \(Output.headline(safety))")))
        for rule in rules {
            let flags = [rule.deep ? t("needs --deep", "--deep 필요") : nil].compactMap { $0 }
            let suffix = flags.isEmpty ? "" : Ansi.dim("  [\(flags.joined(separator: ", "))]")
            print("  \(Ansi.bold(rule.id.rightPadded(to: 26))) \(rule.title)\(suffix)")
            for line in wrap(rule.detail, width: max(40, width - 6)) {
                print("      \(Ansi.dim(line))")
            }
        }
    }
}

func wrap(_ text: String, width: Int) -> [String] {
    var lines: [String] = []
    var current = ""
    for word in text.split(separator: " ") {
        if current.count + word.count + 1 > width {
            lines.append(current)
            current = String(word)
        } else {
            current += current.isEmpty ? String(word) : " \(word)"
        }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
}

// MARK: - doctor

func doctor() {
    Output.printDisk(DiskInfo.current())

    let purgeable = DiskInfo.current().importantAvailableBytes - DiskInfo.current().freeBytes
    if purgeable > 1_000_000_000 {
        print("\n\(Ansi.yellow(t("\(formatBytes(purgeable)) of the reclaimable space is held by the system (purgeable).", "확보 여지 중 \(formatBytes(purgeable)) 는 시스템이 붙들고 있는 공간(purgeable)입니다.")))")
        print(Ansi.dim(t("Usually Time Machine local snapshots:  bium clean --only action-tm-snapshots --level review", "대개 Time Machine 로컬 스냅샷입니다:  bium clean --only action-tm-snapshots --level review")))
    }

    switch Cleaner.trashState() {
    case .empty:
        break
    case .contents(let size):
        print("\n\(t("Trash", "휴지통"))  \(Ansi.bold(formatBytes(size.bytes)))  \(Ansi.dim("bium empty-trash"))")
    case .accessDenied:
        print("\n\(t("Trash", "휴지통"))  \(Ansi.yellow(t("unreadable", "읽을 수 없음"))) — \(t("unreclaimed space may still be sitting here", "여기에 회수되지 않은 공간이 남아 있을 수 있습니다"))")
        print(Ansi.dim(Cleaner.fullDiskAccessHint))
    }

    print("\n\(Ansi.bold(t("Largest places in your home directory", "홈 디렉터리에서 큰 곳")))")
    let sizer = SizeCalculator()
    let ledger = SizeCalculator.LinkLedger()
    let home = Guardrails.home
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
    let paths = entries.map { "\(home)/\($0)" }
    Terminal.status(t("Measuring your home directory… (this can take a while)", "홈 디렉터리 측정 중… (시간이 걸릴 수 있습니다)"))
    let sizes = sizer.sizes(of: paths, ledger: ledger)
    Terminal.clearStatus()

    for (path, size) in sizes.sorted(by: { $0.value.bytes > $1.value.bytes }).prefix(15) {
        guard size.bytes > 100_000_000 else { continue }
        print("  \(Ansi.bold(formatBytes(size.bytes).leftPadded(to: 9)))  \(Terminal.shorten(path, to: 60))")
    }

    print("\n\(Ansi.dim(t("bium only touches your home directory. System areas such as /Library/Caches need root and are deliberately out of scope.", "이 도구는 홈 디렉터리 안만 다룹니다. /Library/Caches 같은 시스템 영역은 root 권한이 필요해 의도적으로 제외했습니다.")))")
    print(Ansi.dim(t("Next:  bium scan", "다음:  bium scan")))
}

exit(run())
