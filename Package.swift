// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DevmachineApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DevmachineCore", targets: ["DevmachineCore"]),
        .library(name: "ClaudeUsageKit", targets: ["ClaudeUsageKit"]),
        .executable(name: "DevmachineApp", targets: ["DevmachineApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "9fc2d2fc627f291727e82d5449ec22df76320671")
    ],
    targets: [
        .target(name: "DevmachineCore"),
        .target(name: "ClaudeUsageKit"),
        .executableTarget(
            name: "DevmachineApp",
            dependencies: [
                "DevmachineCore",
                "ClaudeUsageKit",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .testTarget(
            name: "DevmachineCoreTests",
            dependencies: ["DevmachineCore"]
        ),
        .testTarget(
            name: "ClaudeUsageKitTests",
            dependencies: ["ClaudeUsageKit"]
        ),
        .testTarget(
            name: "DevmachineAppTests",
            dependencies: ["DevmachineApp"]
        )
    ]
)
