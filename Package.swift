// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowMapV2",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WindowMap", targets: ["WindowMap"]),
        .executable(name: "SpreadsheetKitTests", targets: ["SpreadsheetKitTests"]),
        .executable(name: "WindowMapTests", targets: ["WindowMapTests"]),
        .library(name: "Logging", targets: ["Logging"]),
        .library(name: "SpreadsheetKit", targets: ["SpreadsheetKit"]),
        .library(name: "WindowMapCore", targets: ["WindowMapCore"]),
        .library(name: "WindowMapApp", targets: ["WindowMapApp"]),
    ],
    targets: [
        .target(name: "Logging", dependencies: []),
        .target(name: "SpreadsheetKit", dependencies: ["Logging"]),
        .target(name: "WindowMapCore", dependencies: ["Logging"]),
        .target(name: "WindowMapApp", dependencies: ["SpreadsheetKit", "WindowMapCore"]),
        .executableTarget(name: "WindowMap", dependencies: ["SpreadsheetKit", "WindowMapCore", "WindowMapApp"]),
        .executableTarget(name: "SpreadsheetKitTests", dependencies: ["SpreadsheetKit"]),
        .executableTarget(name: "WindowMapTests", dependencies: ["SpreadsheetKit", "WindowMapCore", "WindowMapApp"]),
    ]
)
