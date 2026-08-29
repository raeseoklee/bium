import Foundation
import BiumCore

/// UI text, in the same two languages as the CLI and resolved by the same
/// `t()` so a single LANG decides both.
struct Strings {
    let scan = t("Scan", "검사")
    let doctor = t("Doctor", "진단")
    let rules = t("Rules", "규칙")
    let history = t("History", "기록")
    let tools = t("Tools", "도구")

    let rescan = t("Rescan", "다시 검사")
    let deepScan = t("Deep scan", "깊은 검사")
    let scanning = t("Scanning…", "검사 중…")
    let scanResults = t("Scan results", "검사 결과")
    let nothingFound = t("Nothing to clean at this level.", "이 등급에서는 회수할 공간이 없습니다.")

    let total = t("Total", "전체")
    let available = t("Available", "사용 가능")
    let reclaimable = t("Reclaimable", "확보 가능")
    let inUse = t("In use", "사용 중")
    let used = t("used", "사용")

    let moveToTrash = t("Move to Trash", "휴지통으로 옮기기")
    let deletePermanently = t("Delete permanently", "즉시 삭제")
    let emptyTrash = t("Empty Trash", "휴지통 비우기")
    let cancel = t("Cancel", "취소")
    let grantAccess = t("Open Settings", "권한 열기")

    let trashModeNote = t(
        "Moved to the Trash, so this stays reversible until you empty it.",
        "휴지통으로 옮기므로 비우기 전까지는 되돌릴 수 있습니다."
    )
    let permanentModeNote = t(
        "Deleted immediately. This cannot be undone.",
        "즉시 삭제하며 되돌릴 수 없습니다."
    )
    let aboveSafeWarning = t(
        "Your selection reaches past the SAFE level.",
        "선택한 항목이 SAFE 등급을 넘어섭니다."
    )
    let guardNote = t(
        "Every path is checked again immediately before removal. Anything outside your home directory, a protected path, a .git directory, or a symlink leading out of the rule's scope is refused at that point.",
        "삭제 직전에 모든 경로를 다시 검사합니다. 홈 디렉터리 밖이거나, 보호 경로이거나, .git 디렉터리이거나, 심볼릭 링크로 규칙 범위를 벗어나는 항목은 그 단계에서 거부됩니다."
    )

    func selectionSummary(rules: Int, items: Int) -> String {
        t("\(rules) rules · \(items) items selected", "규칙 \(rules)개 · 항목 \(items)개 선택됨")
    }
    func confirmTitle(_ size: String) -> String {
        t("Move \(size) to the Trash?", "\(size)를 휴지통으로 옮길까요?")
    }
    func confirmTitlePermanent(_ size: String) -> String {
        t("Permanently delete \(size)?", "\(size)를 영구 삭제할까요?")
    }
    func itemCount(_ n: Int) -> String { t("\(n) items", "\(n)개") }
    func ruleCount(_ n: Int) -> String { t("\(n) rules", "규칙 \(n)개") }

    let notScannedTitle = t("Some rules were not scanned", "검사하지 못한 규칙이 있습니다")
    let notScannedBody = t(
        "macOS will not let this app read these locations without Full Disk Access. They are listed here instead of being counted as empty.",
        "전체 디스크 접근 권한이 없어 이 위치들을 읽지 못했습니다. 비어 있다고 세는 대신 여기에 표시합니다."
    )

    let largestPlaces = t("Largest places in your home directory", "홈 디렉터리에서 큰 곳")
    let outsideHomeNote = t(
        "bium only touches your home directory. System areas such as /Library and /opt/homebrew need root and are deliberately out of scope.",
        "bium 은 홈 디렉터리 안만 다룹니다. /Library 나 /opt/homebrew 같은 시스템 영역은 root 권한이 필요하므로 의도적으로 범위에서 제외했습니다."
    )
    let noHistory = t("No cleanups recorded yet.", "아직 정리 기록이 없습니다.")
    let freed = t("Freed", "확보함")
    let cleanedAt = t("Cleaned", "정리 시각")
}

extension SafetyLevel {
    var headline: String {
        switch self {
        case .safe: return t("The machine makes these again", "기기가 다시 만들어 줍니다")
        case .review: return t("Worth a look first", "확인을 권합니다")
        case .caution: return t("May be real data", "실제 데이터일 수 있습니다")
        }
    }
    var blurb: String {
        switch self {
        case .safe: return t("Costs time, never data.", "시간이 걸릴 뿐 데이터를 잃지 않습니다.")
        case .review: return t("Disposable, but the contents vary per person.", "삭제해도 되지만 내용은 사용자마다 다릅니다.")
        case .caution: return t("Selected only when you choose the rule yourself.", "규칙을 직접 선택해야만 대상이 됩니다.")
        }
    }
}
