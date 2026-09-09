// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AurixCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "AurixCore", targets: ["AurixCore"])],
    targets: [.target(name: "AurixCore"), .testTarget(name: "AurixCoreTests", dependencies: ["AurixCore"])]
)
