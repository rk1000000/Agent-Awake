// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AgentAwake",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgentAwakeCore", targets: ["AgentAwakeCore"]),
        .executable(name: "AgentAwake", targets: ["AgentAwake"]),
        .executable(name: "AgentAwakePowerHelper", targets: ["AgentAwakePowerHelper"])
    ],
    targets: [
        .target(
            name: "AgentAwakeCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "AgentAwake",
            dependencies: ["AgentAwakeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "AgentAwakePowerHelper",
            dependencies: ["AgentAwakeCore"]
        ),
        .executableTarget(
            name: "AgentAwakeTests",
            dependencies: ["AgentAwakeCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
