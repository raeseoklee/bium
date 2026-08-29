// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "bium",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "bium", targets: ["bium"]),
        .executable(name: "bium-tests", targets: ["bium-tests"]),
        .executable(name: "BiumApp", targets: ["BiumApp"]),
        .library(name: "BiumCore", targets: ["BiumCore"]),
    ],
    targets: [
        .target(
            name: "BiumCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "bium",
            dependencies: ["BiumCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // A plain executable rather than a .testTarget: XCTest and swift-testing
        // both ship with Xcode, and this project is built against the Command
        // Line Tools SDK alone. `swift run bium-tests`.
        // The SwiftUI front end. Built into a .app bundle by Scripts/build-app.sh
        // rather than by Xcode, so the project stays buildable with just the
        // Command Line Tools.
        .executableTarget(
            name: "BiumApp",
            dependencies: ["BiumCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "bium-tests",
            dependencies: ["BiumCore"],
            path: "Tests/BiumCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
