import Foundation
import BiumCore

enum Ansi {
    static let isTTY = isatty(fileno(stdout)) == 1

    static func wrap(_ text: String, _ code: String) -> String {
        isTTY ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    static func bold(_ t: String) -> String { wrap(t, "1") }
    static func dim(_ t: String) -> String { wrap(t, "2") }
    static func green(_ t: String) -> String { wrap(t, "32") }
    static func yellow(_ t: String) -> String { wrap(t, "33") }
    static func red(_ t: String) -> String { wrap(t, "31") }
    static func cyan(_ t: String) -> String { wrap(t, "36") }

    static var width: Int {
        var w = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0, w.ws_col > 20 {
            return Int(w.ws_col)
        }
        return 100
    }
}

enum Terminal {
    /// Transient single-line status. Suppressed when stdout is piped so JSON
    /// and redirected output stay clean.
    static func status(_ message: String) {
        guard Ansi.isTTY else { return }
        let line = String(message.prefix(Ansi.width - 1))
        FileHandle.standardError.write("\r\u{1B}[2K\(line)".data(using: .utf8)!)
    }

    static func clearStatus() {
        guard Ansi.isTTY else { return }
        FileHandle.standardError.write("\r\u{1B}[2K".data(using: .utf8)!)
    }

    static func error(_ message: String) {
        FileHandle.standardError.write("\(Ansi.red(t("error:", "오류:"))) \(message)\n".data(using: .utf8)!)
    }

    /// Yes/no prompt. Returns false without asking when input is not a terminal,
    /// so a piped invocation can never be silently confirmed.
    static func confirm(_ question: String) -> Bool {
        guard isatty(fileno(stdin)) == 1 else {
            error(t("Cannot read a confirmation. Pass --yes for non-interactive runs.", "확인 입력을 받을 수 없습니다. 비대화형 실행에는 --yes 를 붙이세요."))
            return false
        }
        print("\n\(question) \(Ansi.dim("[y/N]")) ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return answer == "y" || answer == "yes"
    }

    /// Shortens a path from the left so the meaningful tail stays visible.
    static func shorten(_ path: String, to limit: Int) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var display = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        if display.count > limit {
            display = "…" + String(display.suffix(limit - 1))
        }
        return display
    }
}
