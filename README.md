# swift-institute-linter-rules

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Institute-tier lint rule packs for [swift-linter](https://github.com/swift-compositions/swift-linter) — SwiftSyntax-based rules covering naming, typed throws, byte discipline, memory safety, platform layering, and code structure, published together as `Lint.Rule.Bundle.institute`.

---

## Quick Start

A consumer package activates the full institute rule set with a single `Lint.swift` file at its package root, next to `Package.swift`:

```swift
// swift-linter-tools-version: 0.1

import Linter
import Linter_Institute_Rules

Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-compositions/swift-institute-linter-rules.git",
        branch: "main",
        products: ["Linter Institute Rules"]
    ),
]) {
    Lint.Rule.Bundle.institute
}
```

The bundle name is the whole configuration: `Lint.Rule.Bundle.institute` composes the universal-tier bundle with every institute-tier rule pack in this package, so a consumer references one identifier and picks up new rules automatically as packs are added — no per-rule enumeration to keep in sync.

Each rule pack is also published as its own library product (see Architecture below) for consumers that want a subset of the rule set rather than the full bundle.

---

## Installation

For direct use of the rule definitions in Swift code — for example, composing a custom bundle — add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/swift-compositions/swift-institute-linter-rules.git", branch: "main")
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Linter Institute Rules", package: "swift-institute-linter-rules")
    ]
)
```

### Requirements

- Swift 6.3+
- macOS 26.0+, iOS 26.0+, tvOS 26.0+, watchOS 26.0+, visionOS 26.0+

---

## Architecture

| Product | When to import |
|---------|----------------|
| `Linter Institute Rules` | Default. Publishes `Lint.Rule.Bundle.institute` — the universal-tier bundle plus every institute pack below. |
| `Institute Linter Rule <Pack>` | Selective adoption of a single rule pack when the full bundle is unwanted. |

Rule packs, one library product each:

| Pack | Covers |
|------|--------|
| `Naming` | Compound identifiers and type names, namespace adoption, tag suffixes, redundant prefixes, ad-hoc box classes |
| `Foundation` | Foundation imports in Foundation-free targets |
| `Framework` | XCTest imports, swift-testing suite categorization |
| `Byte` | UInt8/Byte discrimination at byte-domain boundaries: conformances, witnesses, forwarders, ASCII extensions |
| `Cardinal` | Cardinal-typed literal construction, `.count - 1` boundary arithmetic |
| `Conformance` | Leaf body typealias presence |
| `Closure` | Closure parameter position, lifecycle-closure ordering and labeling, configuration placement |
| `Idiom` | Iteration intent, enumerated-with-subscript, bounded indices, UTF-8 string scanning |
| `Manifest` | Package manifest dependency-declaration shape |
| `Memory` | Noncopyable extension constraints, pointer arithmetic, Sendable struct shape, unsafe-assignment granularity, unchecked-Sendable anchors |
| `Platform` | C types in public API, platform conditionals, dead cases per platform, platform namespace layering |
| `Workflow` | GitHub Actions job and step condition placement |
| `RawValue` | `.rawValue` chaining and bit-pattern conversion anti-patterns, Tagged-newtype public initializer and unchecked-construction shapes |
| `Structure` | Single type per file, raw-value access, wrapper shapes, minimal type bodies, hoisted protocol aliases |
| `Testing` | Test function naming, performance-suite serialization |
| `Throws` | Typed-throws adoption: untyped and existential throws, typed do-catch, hoisted errors, result-shim patterns |
| `Try` | Optional-try usage |
| `Unchecked` | Unchecked call sites |

Every rule's diagnostic message is meant to state the default disposition (how to fix the finding) and the recognized exemptions, so a finding is actionable without consulting external documentation — reviews occasionally find individual messages that fall short of this and file it as a defect against that rule.

---

## Related Packages

- [swift-linter](https://github.com/swift-compositions/swift-linter) — The lint engine that consumes these packs via `Lint.swift`.
- [swift-linter](https://github.com/swift-molecules/swift-linter) — `Lint.Rule` and source-model primitives the rules are built on.
- swift-linter-rules (public release pending) — Universal-tier rule packs; `Lint.Rule.Bundle.institute` includes its universal bundle.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE](LICENSE.md).
