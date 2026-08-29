import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public var succeeded: Bool { exitCode == 0 }
}

public enum Shell {

    /// Absolute path of `name` on PATH, or nil. Used to decide whether an
    /// action rule is even applicable on this machine.
    public static func which(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        for dir in paths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Runs a command with a hard timeout. Probes during `scan` must never be
    /// able to hang the whole report — a stalled `docker` daemon is common.
    @discardableResult
    public static func run(_ argv: [String], timeout: TimeInterval = 20) -> CommandResult {
        guard let first = argv.first, let executable = which(first) else {
            return CommandResult(exitCode: 127, stdout: "", stderr: t("command not found: \(argv.first ?? "")", "명령을 찾을 수 없음: \(argv.first ?? "")"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: 126, stdout: "", stderr: "\(error)")
        }

        // Read on background queues so a large output cannot deadlock against
        // the pipe buffer while we wait.
        let outData = DataBox()
        let errData = DataBox()
        let group = DispatchGroup()
        for (pipe, box) in [(outPipe, outData), (errPipe, errData)] {
            group.enter()
            DispatchQueue.global().async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return CommandResult(exitCode: 124, stdout: "", stderr: t("timed out after \(Int(timeout))s", "시간 초과 (\(Int(timeout))초)"))
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 5)

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData.data, encoding: .utf8) ?? "",
            stderr: String(data: errData.data, encoding: .utf8) ?? ""
        )
    }

    final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}
