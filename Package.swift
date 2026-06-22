// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MattermostSwift",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "MattermostSwift",
            targets: ["MattermostSwift"]
        ),
        .executable(
            name: "MattermostSwiftCLI",
            targets: ["MattermostSwiftCLI"]
        ),
    ],
    targets: [
        .target(
            name: "MattermostSwift",
            path: "Sourcecode/MattermostSwift"
        ),
        .executableTarget(
            name: "MattermostSwiftCLI",
            dependencies: ["MattermostSwift"],
            path: "Sourcecode/MattermostSwiftCLI"
        ),
        .testTarget(
            name: "MattermostSwiftTests",
            dependencies: ["MattermostSwift", "MattermostSwiftCLI"],
            path: "Tests/MattermostSwiftTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
