// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "fixture",
    products: [.executable(name: "records", targets: ["Records"])],
    targets: [.executableTarget(name: "Records")]
)
