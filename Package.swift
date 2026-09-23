// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HomeStereo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HomeStereoKit", targets: ["HomeStereoKit"]),
        .executable(name: "home-stereo", targets: ["HomeStereoCLI"]),
        .library(name: "HomeStereoAppCore", targets: ["HomeStereoAppCore"]),
        .executable(name: "HomeStereoApp", targets: ["HomeStereoApp"]),
    ],
    targets: [
        .target(name: "HomeStereoKit"),
        .executableTarget(name: "HomeStereoCLI", dependencies: ["HomeStereoKit"]),
        .testTarget(name: "HomeStereoKitTests", dependencies: ["HomeStereoKit"]),
        .target(name: "HomeStereoAppCore"),
        .executableTarget(name: "HomeStereoApp", dependencies: ["HomeStereoAppCore"]),
        .testTarget(name: "HomeStereoAppCoreTests", dependencies: ["HomeStereoAppCore"]),
    ]
)
