// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Vaultline",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Vaultline", targets: ["Vaultline"])],
    targets: [.executableTarget(name: "Vaultline")]
)
