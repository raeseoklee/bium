import Foundation

/// The languages `bium` speaks.
///
/// English is the default because the tool is published for a general audience;
/// Korean exists because that is the language it was written in and the one its
/// safety wording was reasoned about most carefully.
public enum Language: String, Sendable, CaseIterable {
    case en
    case ko

    /// Resolves the language from the environment.
    ///
    /// `BIUM_LANG` wins so a user can override just this tool, then the standard
    /// POSIX chain. Anything unrecognised falls back to English rather than
    /// guessing: a half-translated screen is worse than a consistent one.
    public static func detect(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Language {
        for key in ["BIUM_LANG", "LC_ALL", "LC_MESSAGES", "LANG"] {
            guard let raw = environment[key], !raw.isEmpty else { continue }
            // "ko_KR.UTF-8" -> "ko"
            let code = raw.prefix { $0 != "_" && $0 != "." && $0 != "-" }.lowercased()
            if let match = Language(rawValue: String(code)) { return match }
            // An explicit but unknown locale still means "not Korean".
            return .en
        }
        return .en
    }
}

/// Runtime language selection.
///
/// Set once during startup, before any rule is built — `Rule` bakes its title
/// and detail in at construction time, so changing the language afterwards will
/// not retranslate rules that already exist.
public enum L10n {
    nonisolated(unsafe) public static var language: Language = Language.detect()
}

/// Picks the string for the active language.
///
/// Translations live at the call site rather than in a key table on purpose:
/// there are no keys to drift, nothing can silently fall back to a raw
/// identifier, and a reviewer reads both languages in the same diff.
public func t(_ en: String, _ ko: String) -> String {
    L10n.language == .ko ? ko : en
}
