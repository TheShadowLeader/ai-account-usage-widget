// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageWidget",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AIUsageWidget", targets: ["AIUsageWidget"])],
    targets: [.executableTarget(name: "AIUsageWidget")],
    swiftLanguageModes: [.v5]
)
