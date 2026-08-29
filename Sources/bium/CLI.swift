import Foundation
import BiumCore

enum Command: String {
    case scan
    case clean
    case list
    case doctor
    case emptyTrash = "empty-trash"
    case help
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    var command: Command = .scan
    var level: SafetyLevel = .safe
    /// True when the user named a level explicitly; `clean` warns otherwise.
    var levelWasExplicit = false
    var deep = false
    var includeActions = true
    var only: Set<String> = []
    var exclude: Set<String> = []
    var dryRun = false
    var permanent = false
    var assumeYes = false
    var json = false
    var verbose = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var args = arguments

        if let first = args.first, !first.hasPrefix("-") {
            guard let command = Command(rawValue: first) else {
                throw CLIError(t("unknown command: \(first)", "알 수 없는 명령: \(first)"))
            }
            options.command = command
            args.removeFirst()
        }
        // `clean` defaults to a dry run's worth of caution: only SAFE items,
        // unless the user widens it deliberately.
        if options.command == .scan { options.level = .caution }

        var index = 0
        func nextValue(_ flag: String) throws -> String {
            index += 1
            guard index < args.count else { throw CLIError(t("\(flag) needs a value", "\(flag) 뒤에 값이 필요합니다")) }
            return args[index]
        }

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--level", "-l":
                let raw = try nextValue(arg)
                guard let level = SafetyLevel(rawValue: raw.lowercased()) else {
                    throw CLIError(t("--level must be safe, review or caution (got: \(raw))", "--level 값은 safe / review / caution 중 하나여야 합니다 (받은 값: \(raw))"))
                }
                options.level = level
                options.levelWasExplicit = true
            case "--all":
                options.level = .caution
                options.levelWasExplicit = true
            case "--safe":
                options.level = .safe
                options.levelWasExplicit = true
            case "--deep":
                options.deep = true
            case "--no-actions":
                options.includeActions = false
            case "--only":
                options.only.formUnion(try nextValue(arg).split(separator: ",").map(String.init))
            case "--exclude":
                options.exclude.formUnion(try nextValue(arg).split(separator: ",").map(String.init))
            case "--dry-run", "-n":
                options.dryRun = true
            case "--permanent":
                options.permanent = true
            case "--yes", "-y":
                options.assumeYes = true
            case "--json":
                options.json = true
            case "--verbose", "-v":
                options.verbose = true
            case "--help", "-h":
                options.command = .help
            case "--version":
                print("bium \(version)")
                exit(0)
            default:
                throw CLIError(t("unknown option: \(arg)", "알 수 없는 옵션: \(arg)"))
            }
            index += 1
        }

        let known = Set(Rules.all().map(\.id))
        for id in options.only.union(options.exclude) where !known.contains(id) {
            throw CLIError(t("unknown rule id: \(id)  (run 'bium list')", "알 수 없는 규칙 id: \(id)  ('bium list' 로 확인하세요)"))
        }

        return options
    }

    var scanOptions: ScanOptions {
        ScanOptions(
            deep: deep,
            includeActions: includeActions,
            only: only,
            exclude: exclude
        )
    }
}

let version = "0.1.0"

var helpText: String {
    L10n.language == .ko ? helpKO : helpEN
}

let helpEN = """
\(Ansi.bold("bium")) — reclaim disk space on a Mac, safely

\(Ansi.bold("USAGE"))
  bium <command> [options]

\(Ansi.bold("COMMANDS"))
  scan           survey what can be removed, grouped by safety level (default; deletes nothing)
  clean          actually clean. Defaults to SAFE level only, moving to the Trash
  list           list every rule and its safety level
  doctor         summarise disk state and the largest directories
  empty-trash    empty the Trash (required before space cleaned in trash mode comes back)

\(Ansi.bold("OPTIONS"))
  -l, --level <level>  safe | review | caution — include up to this level (clean defaults to safe)
      --all            same as --level caution
      --deep           walk project trees for stale node_modules and build output (slow)
      --only <id,…>    act on these rules only
      --exclude <id,…> skip these rules
      --no-actions     skip delegated actions such as brew / docker / tmutil
  -n, --dry-run        show what would be removed without removing it
      --permanent      delete immediately instead of using the Trash (not recoverable)
  -y, --yes            skip confirmation prompts
      --json           machine-readable output
  -v, --verbose        show every item path

\(Ansi.bold("SAFETY LEVELS"))
  \(Ansi.green("SAFE"))     the machine makes these again. Costs time, never data.
  \(Ansi.yellow("REVIEW"))   almost certainly disposable, but the contents vary per person. Glance first.
  \(Ansi.red("CAUTION"))  real user data, or expensive to rebuild. Only removed if you name the rule.

\(Ansi.bold("LANGUAGE"))
  English by default. Korean when LANG/LC_ALL starts with "ko",
  or with BIUM_LANG=ko to override just this tool.

\(Ansi.bold("EXAMPLES"))
  bium scan                      survey everything
  bium scan --deep -v            include project output, show all paths
  bium clean --dry-run           preview what SAFE level would remove
  bium clean                     clean SAFE level (to the Trash)
  bium clean --level review      clean up to REVIEW level
  bium clean --only xcode-deriveddata,npm-cache
  bium empty-trash               empty the Trash → this is where space actually returns
"""

let helpKO = """

\(Ansi.bold("bium")) — 맥 디스크 공간 회수 도구

\(Ansi.bold("사용법"))
  bium <명령> [옵션]

\(Ansi.bold("명령"))
  scan           지울 수 있는 것을 안전 등급별로 조사합니다 (기본값, 아무것도 지우지 않음)
  clean          실제로 정리합니다. 기본은 SAFE 등급만, 휴지통으로 이동합니다
  list           모든 규칙과 안전 등급을 나열합니다
  doctor         디스크 현황과 큰 디렉터리를 요약합니다
  empty-trash    휴지통을 비웁니다 (휴지통 모드로 정리한 공간은 이걸 해야 실제로 회수됩니다)

\(Ansi.bold("옵션"))
  -l, --level <등급>   safe | review | caution — 해당 등급까지 포함 (clean 기본값: safe)
      --all            --level caution 과 동일
      --deep           프로젝트 트리를 훑어 오래된 node_modules / 빌드 산출물도 찾습니다 (느림)
      --only <id,…>    해당 규칙만 대상으로 합니다
      --exclude <id,…> 해당 규칙을 제외합니다
      --no-actions     brew / docker / tmutil 같은 위임 작업을 건너뜁니다
  -n, --dry-run        무엇을 지울지만 보여주고 실제로는 지우지 않습니다
      --permanent      휴지통을 거치지 않고 즉시 삭제합니다 (복구 불가)
  -y, --yes            확인 프롬프트를 건너뜁니다
      --json           기계가 읽을 JSON으로 출력합니다
  -v, --verbose        항목별 경로를 모두 보여줍니다

\(Ansi.bold("안전 등급"))
  \(Ansi.green("SAFE"))     기기가 알아서 다시 만드는 것. 시간만 들고 데이터는 잃지 않습니다.
  \(Ansi.yellow("REVIEW"))   거의 확실히 버려도 되지만 내용이 사용자마다 다릅니다. 한번 보고 지우세요.
  \(Ansi.red("CAUTION"))  실제 사용자 데이터이거나 다시 만들기 비싼 것. 규칙을 콕 집어야 지워집니다.

\(Ansi.bold("예시"))
  bium scan                      전체 조사
  bium scan --deep -v            프로젝트 산출물까지, 경로 전부 표시
  bium clean --dry-run           SAFE 등급으로 무엇이 지워질지 미리보기
  bium clean                     SAFE 등급 정리 (휴지통으로)
  bium clean --level review      REVIEW 등급까지 정리
  bium clean --only xcode-deriveddata,npm-cache
  bium empty-trash               휴지통 비우기 → 여기서 실제 공간이 돌아옵니다
"""
