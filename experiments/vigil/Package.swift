// swift-tools-version: 6.0
import PackageDescription

// Layout: Apps/ holds the three programs, Sources/ the libraries they share.
// Each feature lives in Sources/Features/<Name>/ as a <Name>Core (logic, no UI)
// and a <Name>UI target. See docs/ADDING_A_FEATURE.md.
let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vigil", targets: ["Vigil"]),
        .executable(name: "VigilHelper", targets: ["VigilHelper"]),
        .executable(name: "VigilCLI", targets: ["VigilCLI"]),
    ],
    targets: [
        // Shared foundation
        .target(name: "VigilKit", path: "Sources/VigilKit"),
        .target(name: "VigilIPC", dependencies: ["AwakeCore"], path: "Sources/VigilIPC"),
        .target(name: "DesignSystem", path: "Sources/DesignSystem"),

        // Feature: Awake (keep the Mac awake, lid open or closed)
        .target(name: "AwakeCore", path: "Sources/Features/Awake/AwakeCore"),
        .target(name: "AwakeUI", dependencies: ["AwakeCore", "VigilIPC", "VigilKit", "DesignSystem"],
                path: "Sources/Features/Awake/AwakeUI"),

        // Programs
        .executableTarget(name: "Vigil", dependencies: ["VigilKit", "DesignSystem", "AwakeUI"], path: "Apps/Vigil"),
        .executableTarget(name: "VigilHelper", dependencies: ["AwakeCore", "VigilIPC"], path: "Apps/VigilHelper"),
        .executableTarget(name: "VigilCLI", dependencies: ["AwakeCore", "VigilIPC"], path: "Apps/VigilCLI"),

        // Tests
        .testTarget(name: "AwakeCoreTests", dependencies: ["AwakeCore"]),
        .testTarget(name: "VigilIPCTests", dependencies: ["VigilIPC", "AwakeCore"]),
        .testTarget(name: "AwakeUITests", dependencies: ["AwakeUI", "AwakeCore"]),
        .testTarget(name: "VigilKitTests", dependencies: ["VigilKit"]),
        .testTarget(name: "VigilHelperTests", dependencies: ["VigilHelper", "AwakeCore", "VigilIPC"]),
    ]
)
