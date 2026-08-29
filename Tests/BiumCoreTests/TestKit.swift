import Foundation
import BiumCore

/// A deliberately small assertion harness.
///
/// XCTest and swift-testing both ship inside Xcode, and this project targets a
/// machine that only has the Command Line Tools — so the alternative to this
/// file is no tests at all.
enum Check {

    nonisolated(unsafe) private(set) static var passed = 0
    nonisolated(unsafe) private(set) static var failures: [String] = []
    nonisolated(unsafe) private static var currentSuite = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        do {
            try body()
        } catch {
            record("threw during suite: \(error)", line: 0)
        }
    }

    private static func record(_ message: String, line: UInt) {
        failures.append("\(currentSuite):\(line)  \(message)")
    }

    static func expect(_ condition: Bool, _ message: String, line: UInt = #line) {
        if condition { passed += 1 } else { record(message, line: line) }
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: UInt = #line) {
        if actual == expected {
            passed += 1
        } else {
            record("\(message)\n      expected: \(expected)\n      actual:   \(actual)", line: line)
        }
    }

    static func rejects(_ path: String, root: String?, _ message: String, line: UInt = #line) {
        do {
            try Guardrails.validate(path, root: root)
            record("\(message) — should have been rejected but passed: \(path)", line: line)
        } catch {
            passed += 1
        }
    }

    static func accepts(_ path: String, root: String?, _ message: String, line: UInt = #line) {
        do {
            try Guardrails.validate(path, root: root)
            passed += 1
        } catch {
            record("\(message) — should have passed but was rejected: \(path) (\(error))", line: line)
        }
    }

    static func report() -> Int32 {
        let total = passed + failures.count
        if failures.isEmpty {
            print("\u{1B}[32mPASS\u{1B}[0m  all \(total) checks succeeded")
            return 0
        }
        print("\u{1B}[31mFAIL\u{1B}[0m  \(failures.count)/\(total) checks")
        for failure in failures { print("  • \(failure)") }
        return 1
    }
}

// MARK: - Temporary directories

enum TempDir {
    nonisolated(unsafe) static var created: [String] = []

    static func make(_ label: String) throws -> String {
        let path = NSTemporaryDirectory() + "bium-\(label)-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        created.append(path)
        return path
    }

    static func cleanUp() {
        for path in created { try? FileManager.default.removeItem(atPath: path) }
        created.removeAll()
    }

    static func makeDirs(_ root: String, _ names: [String]) throws {
        for name in names {
            try FileManager.default.createDirectory(
                atPath: "\(root)/\(name)", withIntermediateDirectories: true
            )
        }
    }

    static func write(_ bytes: Int, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: URL(fileURLWithPath: path))
    }

    static func age(_ path: String, days: Int) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-Double(days) * 86_400)],
            ofItemAtPath: path
        )
    }
}

