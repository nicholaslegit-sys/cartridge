// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cartridge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cartridge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CartridgeTests",
            dependencies: ["Cartridge"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
