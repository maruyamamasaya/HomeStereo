// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HomeStereo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HomeStereoKit", targets: ["HomeStereoKit"]),
        .library(name: "SonyStereoBridgeAudio", targets: ["SonyStereoBridgeAudio"]),
        .executable(name: "home-stereo", targets: ["HomeStereoCLI"]),
        .executable(name: "sony-stereo-bridge", targets: ["SonyStereoBridgeCLI"]),
        .library(name: "HomeStereoAppCore", targets: ["HomeStereoAppCore"]),
        .executable(name: "HomeStereoApp", targets: ["HomeStereoDLNAApp"]),
    ],
    targets: [
        .target(name: "HomeStereoKit", exclude: ["AGENTS.md"]),
        .executableTarget(name: "HomeStereoCLI", dependencies: ["HomeStereoKit"]),
        .target(name: "SonyStereoBridgeAudio"),
        .executableTarget(name: "SonyStereoBridgeCLI", dependencies: ["HomeStereoKit", "SonyStereoBridgeAudio"]),
        .testTarget(name: "SonyStereoBridgeAudioTests", dependencies: ["SonyStereoBridgeAudio"]),
        .testTarget(name: "HomeStereoKitTests", dependencies: ["HomeStereoKit"]),
        .target(
            name: "HomeStereoAppCore",
            exclude: ["AGENTS.md"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "HomeStereoDLNAAppCore", dependencies: ["HomeStereoKit", "HomeStereoAppCore"]),
        .executableTarget(name: "HomeStereoDLNAApp", dependencies: ["HomeStereoDLNAAppCore", "HomeStereoKit", "HomeStereoAppCore"]),
        .testTarget(name: "HomeStereoAppCoreTests", dependencies: ["HomeStereoAppCore"]),
        .testTarget(name: "HomeStereoDLNAAppCoreTests", dependencies: ["HomeStereoDLNAAppCore", "HomeStereoKit", "HomeStereoAppCore"]),
    ]
)
