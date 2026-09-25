// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AIPulseCore", platforms: [.macOS(.v14)], products: [.library(name: "AIPulseCore", targets: ["AIPulseCore"])], targets: [
    .target(name: "AIPulseCore", path: "Shared", exclude: ["ProviderViews.swift", "SnapshotStore.swift"]),
    .testTarget(name: "AIPulseCoreTests", dependencies: ["AIPulseCore"], path: "Tests")
])
