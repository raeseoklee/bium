import Foundation

/// Turns a probe command's output into "how much would this free, and is it
/// even worth offering".
///
/// Estimates are deliberately conservative: when a tool will not tell us a
/// number we report 0 bytes and explain why, rather than inventing one.
public enum ActionEstimator {

    public struct Estimate {
        public let applicable: Bool
        public let bytes: Int64
        public let note: String?
    }

    public static func estimate(_ kind: ActionSpec.Estimator, output: String) -> Estimate {
        switch kind {
        case .none:
            return Estimate(applicable: true, bytes: 0, note: nil)
        case .brewCleanupDryRun:
            return brewCleanup(output)
        case .dockerSystemDF:
            return dockerDF(output)
        case .timeMachineSnapshots:
            return timeMachineSnapshots(output)
        case .simctlUnavailable:
            return simctlUnavailable(output)
        }
    }

    // "This operation would free approximately 1.2GB of disk space."
    private static func brewCleanup(_ output: String) -> Estimate {
        guard let line = output
            .split(separator: "\n")
            .first(where: { $0.contains("would free approximately") })
        else {
            return Estimate(applicable: false, bytes: 0, note: t("nothing to clean", "정리할 항목 없음"))
        }
        guard let bytes = parseSize(in: String(line)), bytes > 0 else {
            return Estimate(applicable: false, bytes: 0, note: t("nothing to clean", "정리할 항목 없음"))
        }
        return Estimate(applicable: true, bytes: bytes, note: nil)
    }

    // Lines of "Images\t1.5GB (50%)" from `docker system df`.
    private static func dockerDF(_ output: String) -> Estimate {
        var total: Int64 = 0
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            total += parseSize(in: String(parts[1])) ?? 0
        }
        guard total > 0 else {
            return Estimate(applicable: false, bytes: 0, note: t("no reclaimable Docker resources", "회수 가능한 Docker 리소스 없음"))
        }
        return Estimate(applicable: true, bytes: total, note: t("as reported reclaimable by Docker", "Docker가 보고한 회수 가능량"))
    }

    private static func timeMachineSnapshots(_ output: String) -> Estimate {
        let count = output
            .split(separator: "\n")
            .filter { $0.contains("com.apple.TimeMachine") }
            .count
        guard count > 0 else {
            return Estimate(applicable: false, bytes: 0, note: t("no local snapshots", "로컬 스냅샷 없음"))
        }
        // macOS does not expose per-snapshot size, and thinning frees a variable
        // amount depending on what has changed since each snapshot was taken.
        return Estimate(
            applicable: true, bytes: 0,
            note: t("\(count) snapshot(s) — the amount freed is only known after running (usually several GB)", "스냅샷 \(count)개 — 회수량은 실행 후에만 알 수 있습니다 (보통 수 GB)")
        )
    }

    private static func simctlUnavailable(_ output: String) -> Estimate {
        guard
            let data = output.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = root["devices"] as? [String: Any]
        else {
            return Estimate(applicable: false, bytes: 0, note: t("could not parse simctl output", "simctl 출력을 해석하지 못함"))
        }

        var udids: [String] = []
        for (_, value) in devices {
            guard let list = value as? [[String: Any]] else { continue }
            for device in list {
                let available = device["isAvailable"] as? Bool ?? true
                if !available, let udid = device["udid"] as? String { udids.append(udid) }
            }
        }
        guard !udids.isEmpty else {
            return Estimate(applicable: false, bytes: 0, note: t("no unavailable simulators", "사용 불가 시뮬레이터 없음"))
        }

        // We can measure this one precisely: each device is a directory on disk.
        let base = "\(Guardrails.home)/Library/Developer/CoreSimulator/Devices"
        let sizer = SizeCalculator()
        let ledger = SizeCalculator.LinkLedger()
        let sizes = sizer.sizes(of: udids.map { "\(base)/\($0)" }, ledger: ledger)
        let total = sizes.values.reduce(Int64(0)) { $0 + $1.bytes }

        return Estimate(applicable: true, bytes: total, note: t("\(udids.count) device(s)", "기기 \(udids.count)개"))
    }

    /// Pulls the first "1.2GB" / "512 MB" style figure out of a line.
    public static func parseSize(in text: String) -> Int64? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let valueRange = Range(match.range(at: 1), in: text),
            let unitRange = Range(match.range(at: 2), in: text),
            let value = Double(text[valueRange])
        else { return nil }

        let unit = text[unitRange].uppercased()
        let multiplier: Double
        switch unit.first {
        case "K": multiplier = 1_000
        case "M": multiplier = 1_000_000
        case "G": multiplier = 1_000_000_000
        case "T": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        // Homebrew and Docker both report decimal units despite writing "GB".
        return Int64(value * multiplier)
    }
}
