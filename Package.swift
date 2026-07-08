// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AquaChat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AquaChat", targets: ["AquaChat"])
    ],
    targets: [
        .executableTarget(
            name: "AquaChat",
            path: "AquaChat",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
