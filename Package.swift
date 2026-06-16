// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MattermostSwift",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
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
            dependencies: ["MattermostSwift"],
            path: "Tests/MattermostSwiftTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
