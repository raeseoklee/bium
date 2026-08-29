import Foundation
import BiumCore

func runLocalizationTests() {
    Check.suite("language/detection") {
        let cases: [([String: String], Language, String)] = [
            ([:], .en, "no locale set at all"),
            (["LANG": "ko_KR.UTF-8"], .ko, "LANG=ko_KR.UTF-8"),
            (["LANG": "ko"], .ko, "bare ko"),
            (["LANG": "en_US.UTF-8"], .en, "LANG=en_US.UTF-8"),
            (["LANG": "C"], .en, "LANG=C"),
            (["LANG": "fr_FR.UTF-8"], .en, "an unsupported locale falls back to English"),
            (["LANG": ""], .en, "an empty LANG is ignored"),
            // BIUM_LANG wins so a user can override this one tool.
            (["LANG": "ko_KR.UTF-8", "BIUM_LANG": "en"], .en, "BIUM_LANG overrides LANG"),
            (["LANG": "en_US.UTF-8", "BIUM_LANG": "ko"], .ko, "BIUM_LANG opts into Korean"),
            // POSIX precedence: LC_ALL beats LC_MESSAGES beats LANG.
            (["LC_ALL": "ko_KR.UTF-8", "LANG": "en_US.UTF-8"], .ko, "LC_ALL beats LANG"),
            (["LC_MESSAGES": "ko_KR.UTF-8", "LANG": "en_US.UTF-8"], .ko, "LC_MESSAGES beats LANG"),
        ]
        for (env, expected, note) in cases {
            Check.equal(Language.detect(env), expected, note)
        }
    }

    Check.suite("language/string selection") {
        let previous = L10n.language
        defer { L10n.language = previous }

        L10n.language = .en
        Check.equal(t("English", "한국어"), "English", "English is selected")
        L10n.language = .ko
        Check.equal(t("English", "한국어"), "한국어", "Korean is selected")
    }

    // Every rule must carry both languages, or a user hits a half-translated
    // screen — which is exactly what the fallback rules are meant to prevent.
    Check.suite("language/every rule is translated") {
        let previous = L10n.language
        defer { L10n.language = previous }

        L10n.language = .en
        let english = Rules.all().map { ($0.id, $0.title, $0.detail) }
        L10n.language = .ko
        let korean = Dictionary(uniqueKeysWithValues: Rules.all().map { ($0.id, ($0.title, $0.detail)) })

        func hasHangul(_ s: String) -> Bool { s.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }

        for (id, enTitle, enDetail) in english {
            guard let (koTitle, koDetail) = korean[id] else {
                Check.expect(false, "rule \(id) is missing from the Korean catalogue")
                continue
            }
            Check.expect(!hasHangul(enTitle), "\(id): English title still contains Hangul")
            Check.expect(!hasHangul(enDetail), "\(id): English detail still contains Hangul")
            // Proper nouns like "Xcode DerivedData" are legitimately identical,
            // so only the long-form detail must actually differ.
            Check.expect(koDetail != enDetail, "\(id): detail is not translated")
            Check.expect(!koTitle.isEmpty && !koDetail.isEmpty, "\(id): empty Korean text")
        }
    }
}
