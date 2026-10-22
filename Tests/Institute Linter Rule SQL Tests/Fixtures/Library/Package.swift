// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "fixture",
    products: [.library(name: "Records", targets: ["Records"])],
    targets: [.target(name: "Records")]
)
