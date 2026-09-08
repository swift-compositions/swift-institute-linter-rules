// swift-tools-version: 6.3.3

// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-institute-linter-rules open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-institute-linter-rules project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
  name: "swift-institute-linter-rules",
  platforms: [
    .macOS("27"),
    .iOS("27"),
    .tvOS("27"),
    .watchOS("27"),
    .visionOS("27"),
  ],
  products: [
    // Architecture pack (TX-A2, swift-compositions/swift-linter#44) —
    // AST-local architecture predicates; derived-model enforcement
    // binds at TX-A4, not here.
    .library(
      name: "Institute Linter Rule Architecture",
      targets: ["Institute Linter Rule Architecture"]
    ),
    .library(
      name: "Institute Linter Rule Naming",
      targets: ["Institute Linter Rule Naming"]
    ),
    .library(
      name: "Institute Linter Rule Foundation",
      targets: ["Institute Linter Rule Foundation"]
    ),
    .library(
      name: "Institute Linter Rule Framework",
      targets: ["Institute Linter Rule Framework"]
    ),
    .library(
      name: "Institute Linter Rule Byte",
      targets: ["Institute Linter Rule Byte"]
    ),
    .library(
      name: "Institute Linter Rule Conformance",
      targets: ["Institute Linter Rule Conformance"]
    ),
    // Wave 3 (2026-05-15) — relocated from swift-linter-rules per
    // the three-tier linter-rules partition note.
    .library(
      name: "Institute Linter Rule Closure",
      targets: ["Institute Linter Rule Closure"]
    ),
    .library(
      name: "Institute Linter Rule Idiom",
      targets: ["Institute Linter Rule Idiom"]
    ),
    // Manifest pack (swift-institute-linter-rules#4) — rules whose
    // surface is the SwiftPM package manifest rather than ordinary
    // source files.
    .library(
      name: "Institute Linter Rule Manifest",
      targets: ["Institute Linter Rule Manifest"]
    ),
    .library(
      name: "Institute Linter Rule Memory",
      targets: ["Institute Linter Rule Memory"]
    ),
    .library(
      name: "Institute Linter Rule Platform",
      targets: ["Institute Linter Rule Platform"]
    ),
    .library(
      name: "Institute Linter Rule Structure",
      targets: ["Institute Linter Rule Structure"]
    ),
    .library(
      name: "Institute Linter Rule Testing",
      targets: ["Institute Linter Rule Testing"]
    ),
    .library(
      name: "Institute Linter Rule Throws",
      targets: ["Institute Linter Rule Throws"]
    ),
    .library(
      name: "Institute Linter Rule Try",
      targets: ["Institute Linter Rule Try"]
    ),
    .library(
      name: "Institute Linter Rule Unchecked",
      targets: ["Institute Linter Rule Unchecked"]
    ),
    // A5 move (2026-07-07) — brand-consumer rule packs relocated from
    // swift-primitives-linter-rules so they enforce at L2/L3 too (brands
    // are defined at L1 but consumed everywhere). Precedent: [PRIM-FOUND-001].
    .library(
      name: "Institute Linter Rule RawValue",
      targets: ["Institute Linter Rule RawValue"]
    ),
    .library(
      name: "Institute Linter Rule Cardinal",
      targets: ["Institute Linter Rule Cardinal"]
    ),

    // Aggregate bundle — re-exports every pack in this package and
    // the upstream universal bundle, publishing
    // `Lint.Rule.Bundle.institute`. Consumers that want the full
    // institute-tier rule set pull this product alone.
    .library(
      name: "Linter Institute Rules",
      targets: ["Linter Institute Rules"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/swift-molecules/swift-lint.git", branch: "main"),
    .package(
      url: "https://github.com/swift-atoms/swift-cardinal.git", branch: "main"),
    .package(url: "https://github.com/swift-atoms/swift-byte.git", branch: "main"),
    .package(url: "https://github.com/swift-compositions/swift-linter-rules.git", branch: "main"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.2"..<"604.0.0"),
  ],
  targets: [
    // Architecture pack (TX-A2, swift-compositions/swift-linter#44).
    .target(
      name: "Institute Linter Rule Architecture",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Naming",
      dependencies: [
        .product(name: "Byte", package: "swift-byte"),
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Foundation",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Framework",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Byte",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Conformance",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Closure",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Idiom",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    // Manifest pack (swift-institute-linter-rules#4).
    .target(
      name: "Institute Linter Rule Manifest",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Memory",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Platform",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Structure",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "Linter Rule Structure", package: "swift-linter-rules"),
        .product(name: "Cardinal", package: "swift-cardinal"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Testing",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Throws",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Try",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Unchecked",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    // A5 move (2026-07-07) — relocated from swift-primitives-linter-rules.
    .target(
      name: "Institute Linter Rule RawValue",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Institute Linter Rule Cardinal",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftOperators", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Linter Institute Rules",
      dependencies: [
        .product(name: "Lint", package: "swift-lint"),
        // Architecture pack (TX-A2, swift-compositions/swift-linter#44).
        .target(name: "Institute Linter Rule Architecture"),
        .target(name: "Institute Linter Rule Naming"),
        .target(name: "Institute Linter Rule Foundation"),
        .target(name: "Institute Linter Rule Framework"),
        .target(name: "Institute Linter Rule Byte"),
        .target(name: "Institute Linter Rule Conformance"),
        .target(name: "Institute Linter Rule Closure"),
        .target(name: "Institute Linter Rule Idiom"),
        // Manifest pack (swift-institute-linter-rules#4).
        .target(name: "Institute Linter Rule Manifest"),
        .target(name: "Institute Linter Rule Memory"),
        .target(name: "Institute Linter Rule Platform"),
        .target(name: "Institute Linter Rule Structure"),
        .target(name: "Institute Linter Rule Testing"),
        .target(name: "Institute Linter Rule Throws"),
        .target(name: "Institute Linter Rule Try"),
        .target(name: "Institute Linter Rule Unchecked"),
        // A5 move (2026-07-07) — relocated from swift-primitives-linter-rules.
        .target(name: "Institute Linter Rule RawValue"),
        .target(name: "Institute Linter Rule Cardinal"),
        .product(name: "Linter Rules", package: "swift-linter-rules"),
      ]
    ),
    // Architecture pack (TX-A2, swift-compositions/swift-linter#44).
    .testTarget(
      name: "Institute Linter Rule Architecture Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Architecture"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Naming Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Naming"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Foundation Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Foundation"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Framework Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Framework"),
        .product(name: "Linter Rule Testing", package: "swift-linter-rules"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Byte Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Byte"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Conformance Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Conformance"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Closure Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Closure"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Idiom Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Idiom"),
        .product(name: "Linter Rule Testing", package: "swift-linter-rules"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    // Manifest pack (swift-institute-linter-rules#4).
    .testTarget(
      name: "Institute Linter Rule Manifest Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Manifest"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Memory Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Memory"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Platform Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Platform"),
        .product(name: "Linter Rule Testing", package: "swift-linter-rules"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Structure Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Structure"),
        .product(name: "Linter Rule Structure", package: "swift-linter-rules"),
        .product(name: "Linter Rule Testing", package: "swift-linter-rules"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Testing Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Testing"),
        .product(name: "Linter Rule Testing", package: "swift-linter-rules"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Throws Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Throws"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Try Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Try"),
        .product(name: "Byte", package: "swift-byte"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Unchecked Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Unchecked"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    // A5 move (2026-07-07) — relocated from swift-primitives-linter-rules.
    .testTarget(
      name: "Institute Linter Rule RawValue Tests",
      dependencies: [
        .target(name: "Institute Linter Rule RawValue"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "Institute Linter Rule Cardinal Tests",
      dependencies: [
        .target(name: "Institute Linter Rule Cardinal"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    // #26 — the aggregate `Lint.Rule.Bundle.institute` had no test
    // target of its own; every hand-verified fact from the #1 review
    // (composition drift, the one deliberate exclusion, id
    // uniqueness, no collision with the universal tier) is now a
    // standing gate instead of a receipt.
    .testTarget(
      name: "Linter Institute Rules Tests",
      dependencies: [
        .target(name: "Linter Institute Rules"),
        .product(name: "Linter Rules", package: "swift-linter-rules"),
        .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
  let ecosystem: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableExperimentalFeature("SuppressedAssociatedTypes"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("LifetimeDependence"),
  ]

  target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
