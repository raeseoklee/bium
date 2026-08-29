import Foundation
import BiumCore

/// The tests that matter most: everything else costs the user time, but a hole
/// in the guardrails costs them data.
func runGuardrailTests() {
    let home = Guardrails.home

    Check.suite("guardrails/protected paths") {
        Check.rejects("/", root: nil, "the filesystem root")
        Check.rejects(home, root: nil, "the home directory itself")
        for name in ["Library", "Documents", "Desktop", "Downloads", "Library/Caches", ".Trash", ".ssh"] {
            Check.rejects("\(home)/\(name)", root: nil, "top-level user directory \(name)")
        }
    }

    Check.suite("guardrails/outside home") {
        Check.rejects("/Library/Caches/something", root: nil, "system caches")
        Check.rejects("/Applications/Safari.app", root: nil, "applications")
        Check.rejects("/usr/local/lib", root: nil, "usr/local")
        Check.rejects("Library/Caches/x", root: nil, "a relative path")
    }

    Check.suite("guardrails/rule scope") {
        Check.rejects(
            "\(home)/Library/Caches/../../Documents", root: "\(home)/Library/Caches",
            "parent traversal (..)"
        )
        Check.rejects(
            "\(home)/Documents/taxes", root: "\(home)/Library/Caches",
            "outside the root the rule declared"
        )
        Check.rejects(
            "\(home)/Library/Caches/project/.git", root: "\(home)/Library/Caches",
            "a .git directory, wherever it sits"
        )
        Check.accepts(
            "\(home)/Library/Caches/com.example.app", root: "\(home)/Library/Caches",
            "an ordinary cache entry"
        )
    }

    // The case that motivated resolving symlinks on the parent: a link planted
    // inside a cache directory must not become a handle on Documents.
    Check.suite("guardrails/symlink escape") {
        let realRoot = "\(home)/Library/Caches/bium-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: realRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: realRoot) }

        let link = "\(realRoot)/escape"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "\(home)/Documents")

        // Unlinking the symlink itself is fine — it stays inside the root.
        Check.accepts(link, root: realRoot, "unlinking the symlink itself")
        // Reaching *through* it is not.
        Check.rejects("\(link)/secret.txt", root: realRoot, "reaching through the link, out of scope")
    }
}
