// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DevmachineApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DevmachineCore", targets: ["DevmachineCore"]),
        .library(name: "HarnessUsageKit", targets: ["HarnessUsageKit"]),
        .executable(name: "DevmachineApp", targets: ["DevmachineApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "9fc2d2fc627f291727e82d5449ec22df76320671"),
        .package(path: "Packages/HighlightSwift"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0")
    ],
    targets: [
        .target(name: "DevmachineCore"),
        .target(name: "HarnessUsageKit"),
        .executableTarget(
            name: "DevmachineApp",
            dependencies: [
                "DevmachineCore",
                "HarnessUsageKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "HighlightSwift", package: "HighlightSwift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        ),
        .testTarget(
            name: "DevmachineCoreTests",
            dependencies: ["DevmachineCore"]
        ),
        .testTarget(
            name: "HarnessUsageKitTests",
            dependencies: ["HarnessUsageKit"]
        ),
        .testTarget(
            name: "HighlightSwiftTests",
            dependencies: [.product(name: "HighlightSwift", package: "HighlightSwift")]
        ),
        .testTarget(
            name: "DevmachineAppTests",
            dependencies: ["DevmachineApp"]
        )
    ]
)
