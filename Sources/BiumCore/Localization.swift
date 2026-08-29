import Foundation

/// Package-wide constants.
///
/// The version lives here so the CLI, the app bundle's Info.plist and the
/// Homebrew formulae cannot drift apart: `Scripts/build-app.sh` substitutes
/// this value into the plist, and `Scripts/release.sh` checks it against the
/// git tag before anything is published.
public enum Bium {
    public static let version = "0.1.2"
}

/// The languages `bium` speaks.
///
/// English is the default because the tool is published for a general audience;
/// Korean exists because that is the language it was written in and the one its
/// safety wording was reasoned about most carefully.
public enum Language: String, Sendable, CaseIterable {
    case en
    case ko

    /// Resolves the language from the environment, then from the system's own
    /// language preference.
    ///
    /// `BIUM_LANG` wins so a user can override just this tool, then the standard
    /// POSIX chain. `preferredLanguages` is the fallback because an app launched
    /// from Finder or the Dock goes through LaunchServices, which passes no
    /// `LANG` at all; without it the window would sit in English on a machine
    /// set to Korean.
    ///
    /// An explicit but unsupported locale stops at English rather than falling
    /// through to the system preference: someone who asked for French should not
    /// be handed Korean, and a half-translated screen is worse than a consistent
    /// one.
    public static func detect(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Language {
        for key in ["BIUM_LANG", "LC_ALL", "LC_MESSAGES", "LANG"] {
            guard let raw = environment[key], !raw.isEmpty else { continue }
            if let match = language(from: raw) { return match }
            return .en
        }
        for identifier in preferredLanguages {
            if let match = language(from: identifier) { return match }
        }
        return .en
    }

    /// "ko_KR.UTF-8" and "ko-KR" both reduce to "ko".
    private static func language(from identifier: String) -> Language? {
        let code = identifier.prefix { $0 != "_" && $0 != "." && $0 != "-" }.lowercased()
        return Language(rawValue: String(code))
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
