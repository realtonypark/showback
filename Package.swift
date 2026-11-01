// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Showback",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "showback", targets: ["Showback"])],
    targets: [
        .target(name: "ShowbackCore", resources: [.process("Resources")]),
        .executableTarget(name: "Showback", dependencies: ["ShowbackCore"]),
        .testTarget(name: "ShowbackCoreTests", dependencies: ["ShowbackCore"])
    ],
    swiftLanguageModes: [.v5]
)
