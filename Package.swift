// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MultiLLMTerminal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MultiLLMTerminal",
            targets: ["MultiLLMTerminal"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MultiLLMTerminal",
            path: "Sources/MultiLLMTerminal"
        )
    ]
)
