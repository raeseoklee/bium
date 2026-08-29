import Foundation
import BiumCore

// The suite asserts on user-facing text, so pin the language: otherwise these
// tests pass or fail depending on the LANG of whoever runs them.
L10n.language = .en

runLocalizationTests()
runGuardrailTests()
try runVersionedPathsTests()
try runScannerTests()
try runSizeCalculatorTests()
runEstimatorTests()

TempDir.cleanUp()
exit(Check.report())
