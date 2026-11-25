// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiteControl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LiteControl", targets: ["LiteControl"])],
    targets: [.executableTarget(name: "LiteControl", path: "Sources/LiteControl")]
)
