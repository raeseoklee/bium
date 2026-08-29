import Foundation

public struct PathSize: Sendable {
    public let bytes: Int64
    public let fileCount: Int
    public let newestModification: Date?

    public static let zero = PathSize(bytes: 0, fileCount: 0, newestModification: nil)
}

/// Measures on-disk usage the way the disk actually sees it.
///
/// Two details matter for a cleaner's numbers to be honest:
/// * We use *allocated* size, not logical size, so APFS compression and block
///   rounding are reflected. This is what `df` will change by.
/// * Hard-linked files are counted once. pnpm stores and Homebrew cellars are
///   full of them, and naive counting inflates the promised savings several-fold.
public struct SizeCalculator: Sendable {

    /// Tracks hard links already counted, so two rules measuring linked copies
    /// of the same blocks do not both claim the space.
    public final class LinkLedger: @unchecked Sendable {
        private var seen = Set<FileID>()
        private let lock = NSLock()

        public init() {}

        func claim(_ id: FileID) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return seen.insert(id).inserted
        }
    }

    struct FileID: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    public init() {}

    /// Size of a single path. Directories are walked; symlinks are never followed.
    public func size(of path: String, ledger: LinkLedger? = nil) -> PathSize {
        var st = stat()
        guard lstat(path, &st) == 0 else { return .zero }

        if (st.st_mode & S_IFMT) != S_IFDIR {
            // A symlink or regular file: its own blocks only.
            let bytes = countable(st, ledger: ledger)
            return PathSize(
                bytes: bytes,
                fileCount: 1,
                newestModification: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            )
        }

        var total: Int64 = Int64(st.st_blocks) * 512
        var files = 0
        var newest = TimeInterval(st.st_mtimespec.tv_sec)

        // fts(3) walks a tree far faster than FileManager.enumerator and gives
        // us the stat buffer directly, which is exactly what we need.
        path.withCString { cPath in
            var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cPath), nil]
            defer { free(paths[0]) }

            guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
            defer { fts_close(stream) }

            while let entry = fts_read(stream) {
                let info = Int32(entry.pointee.fts_info)
                // FTS_D is the pre-order visit; skipping it avoids double-counting
                // directories, which we pick up on the post-order FTS_DP visit.
                guard info != FTS_D, info != FTS_DNR, info != FTS_ERR, info != FTS_NS else { continue }
                guard let sp = entry.pointee.fts_statp else { continue }
                // The root itself was already counted above.
                if entry.pointee.fts_level == 0 { continue }

                let s = sp.pointee
                total += countable(s, ledger: ledger)
                if (s.st_mode & S_IFMT) != S_IFDIR { files += 1 }
                newest = max(newest, TimeInterval(s.st_mtimespec.tv_sec))
            }
        }

        return PathSize(
            bytes: total,
            fileCount: files,
            newestModification: Date(timeIntervalSince1970: newest)
        )
    }

    /// Blocks attributable to this entry, or 0 if another hard link already claimed them.
    private func countable(_ s: stat, ledger: LinkLedger?) -> Int64 {
        let bytes = Int64(s.st_blocks) * 512
        guard s.st_nlink > 1, let ledger else { return bytes }
        let id = FileID(device: s.st_dev, inode: s.st_ino)
        return ledger.claim(id) ? bytes : 0
    }

    /// Sizes many paths concurrently, sharing one ledger so hard links are
    /// counted once across the whole scan.
    public func sizes(of paths: [String], ledger: LinkLedger) -> [String: PathSize] {
        guard !paths.isEmpty else { return [:] }
        let results = ResultBox()
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let path = paths[index]
            let size = self.size(of: path, ledger: ledger)
            results.set(path, size)
        }
        return results.value
    }

    final class ResultBox: @unchecked Sendable {
        private var storage: [String: PathSize] = [:]
        private let lock = NSLock()

        func set(_ key: String, _ value: PathSize) {
            lock.lock()
            storage[key] = value
            lock.unlock()
        }

        var value: [String: PathSize] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
