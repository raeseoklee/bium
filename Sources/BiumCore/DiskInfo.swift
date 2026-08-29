import Foundation

public struct DiskInfo: Sendable, Codable {
    public let volume: String
    public let totalBytes: Int64
    /// What the filesystem reports as free right now.
    public let freeBytes: Int64
    /// What macOS says it could make available, including purgeable space
    /// (local snapshots, caches it manages itself). Usually larger than `freeBytes`.
    public let importantAvailableBytes: Int64

    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public init(volume: String, totalBytes: Int64, freeBytes: Int64, importantAvailableBytes: Int64) {
        self.volume = volume
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.importantAvailableBytes = importantAvailableBytes
    }

    public static func current(for path: String = NSHomeDirectory()) -> DiskInfo {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        return DiskInfo(
            volume: values?.volumeName ?? "/",
            totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            freeBytes: Int64(values?.volumeAvailableCapacity ?? 0),
            importantAvailableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
