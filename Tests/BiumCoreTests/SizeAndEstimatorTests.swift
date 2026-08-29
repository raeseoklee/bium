import Foundation
import BiumCore

func runSizeCalculatorTests() throws {
    let sizer = SizeCalculator()

    Check.suite("sizing/nested files") {
        let dir = try TempDir.make("size")
        try TempDir.write(40_000, to: "\(dir)/a/one.bin")
        try TempDir.write(40_000, to: "\(dir)/a/b/two.bin")
        let size = sizer.size(of: dir)
        Check.equal(size.fileCount, 2, "two files")
        Check.expect(size.bytes >= 80_000, "total must be at least 80KB (got \(size.bytes))")
    }

    // pnpm stores and Homebrew cellars are mostly hard links. Counting each link
    // separately would promise several times the space actually available.
    Check.suite("sizing/hard links counted once") {
        let dir = try TempDir.make("link")
        let original = "\(dir)/original.bin"
        try TempDir.write(200_000, to: original)
        try FileManager.default.linkItem(atPath: original, toPath: "\(dir)/link.bin")

        let size = sizer.size(of: dir, ledger: SizeCalculator.LinkLedger())
        Check.equal(size.fileCount, 2, "still two files")
        Check.expect(size.bytes < 300_000, "the bytes must be counted once (got \(size.bytes))")
        Check.expect(size.bytes >= 200_000, "the original size must be included (got \(size.bytes))")
    }

    // A symlinked directory must not be walked, or a link into the home folder
    // would make a small cache appear to be hundreds of gigabytes.
    Check.suite("sizing/symlinked directories are not followed") {
        let dir = try TempDir.make("symlink")
        let payload = try TempDir.make("payload")
        try TempDir.write(500_000, to: "\(payload)/big.bin")
        try FileManager.default.createSymbolicLink(atPath: "\(dir)/link", withDestinationPath: payload)

        let size = sizer.size(of: dir)
        Check.expect(size.bytes < 100_000, "the link target must not be counted (got \(size.bytes))")
    }

    Check.suite("sizing/missing path") {
        let size = sizer.size(of: "/nonexistent-\(UUID().uuidString)")
        Check.equal(size.bytes, 0, "zero bytes")
        Check.equal(size.fileCount, 0, "zero files")
    }
}

func runEstimatorTests() {
    Check.suite("estimates/size parsing") {
        Check.equal(ActionEstimator.parseSize(in: "1.5GB") ?? -1, 1_500_000_000, "1.5GB")
        Check.equal(ActionEstimator.parseSize(in: "approximately 512MB of disk") ?? -1, 512_000_000, "512MB")
        Check.equal(ActionEstimator.parseSize(in: "0B (0%)") ?? -1, 0, "0B")
        Check.expect(ActionEstimator.parseSize(in: "nothing here") == nil, "no number means nil")
    }

    Check.suite("estimates/Homebrew") {
        Check.expect(
            !ActionEstimator.estimate(.brewCleanupDryRun, output: "==> No cached downloads\n").applicable,
            "nothing to clean means nothing offered"
        )
        let output = "Would remove: /Users/x/Library/Caches/Homebrew/foo\n"
            + "==> This operation would free approximately 2.3GB of disk space.\n"
        let estimate = ActionEstimator.estimate(.brewCleanupDryRun, output: output)
        Check.expect(estimate.applicable, "offered when there is something to reclaim")
        Check.equal(estimate.bytes, 2_300_000_000, "2.3GB")
    }

    Check.suite("estimates/Docker") {
        let output = "Images\t1.5GB (60%)\nBuild Cache\t500MB (100%)\nContainers\t0B (0%)\n"
        let estimate = ActionEstimator.estimate(.dockerSystemDF, output: output)
        Check.expect(estimate.applicable, "offered when reclaimable")
        Check.equal(estimate.bytes, 2_000_000_000, "sum of the rows")
    }

    // Thinning frees an amount macOS will not disclose in advance, so the
    // estimate stays at zero rather than inventing a number.
    Check.suite("estimates/Time Machine snapshots") {
        Check.expect(
            !ActionEstimator.estimate(.timeMachineSnapshots, output: "Snapshots for volume group disk3:\n").applicable,
            "no snapshots means nothing offered"
        )
        let output = """
        Snapshots for volume group disk3:
        com.apple.TimeMachine.2026-08-28-120000.local
        com.apple.TimeMachine.2026-08-29-120000.local
        """
        let estimate = ActionEstimator.estimate(.timeMachineSnapshots, output: output)
        Check.expect(estimate.applicable, "offered when snapshots exist")
        Check.equal(estimate.bytes, 0, "no byte estimate is invented")
        Check.expect(estimate.note?.contains("2 snapshot") == true, "the count is reported")
    }
}
