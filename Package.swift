// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DesktopPet",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DesktopPetTests",
            dependencies: ["DesktopPet"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
