// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuotaPet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexQuotaPetCore", targets: ["CodexQuotaPetCore"]),
        .executable(name: "CodexQuotaPet", targets: ["CodexQuotaPet"]),
        .executable(name: "CodexQuotaPetSelfTests", targets: ["CodexQuotaPetSelfTests"])
    ],
    targets: [
        .target(
            name: "CodexQuotaPetCore",
            path: "Sources/CodexQuotaPetCore"
        ),
        .executableTarget(
            name: "CodexQuotaPet",
            dependencies: ["CodexQuotaPetCore"],
            path: "Sources/CodexQuotaPet"
        ),
        .executableTarget(
            name: "CodexQuotaPetSelfTests",
            dependencies: ["CodexQuotaPetCore"],
            path: "Sources/CodexQuotaPetSelfTests"
        )
    ]
)
