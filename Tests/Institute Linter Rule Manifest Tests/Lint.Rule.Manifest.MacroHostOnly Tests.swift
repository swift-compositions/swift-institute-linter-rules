import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Manifest

extension Lint.Rule {
    @Suite
    struct `macro host only Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

extension Lint.Rule.`macro host only Tests` {
    static func findings(_ manifest: Swift::String) -> [Diagnostic.Record] {
        Lint.Rule.`macro host only`
            .observe(Lint.Source.parsed(from: manifest, file: "Package.swift"), .warning)
            .findings
    }
}

extension Lint.Rule.`macro host only Tests`.Unit {
    @Test
    func `macro implementation sharing an ordinary dependency is flagged`() {
        let manifest = """
            let package = Package(
              targets: [
                .target(name: "Standard Library Extensions"),
                .macro(
                  name: "SQL Macros Implementation",
                  dependencies: [.target(name: "Standard Library Extensions")]
                ),
                .target(
                  name: "SQL",
                  dependencies: [.target(name: "Standard Library Extensions")]
                ),
              ]
            )
            """
        let findings = Lint.Rule.`macro host only Tests`.findings(manifest)
        #expect(findings.count == 1)
        #expect(findings.first?.severity == .warning)
        #expect(findings.first?.message == manifestMacroHostOnlyMessage)
    }

    @Test
    func `macro test sharing the wrapper library is flagged`() {
        let manifest = """
            let package = Package(
              targets: [
                .macro(name: "SQL Macros Implementation"),
                .target(
                  name: "SQL Macros",
                  dependencies: [.target(name: "SQL Macros Implementation")]
                ),
                .testTarget(
                  name: "SQL Macros Tests",
                  dependencies: [
                    .target(name: "SQL Macros Implementation"),
                    .target(name: "SQL Macros"),
                  ]
                ),
              ]
            )
            """
        #expect(Lint.Rule.`macro host only Tests`.findings(manifest).count == 1)
    }

    @Test
    func `host-only macro core and syntax products are lawful`() {
        let manifest = """
            let package = Package(
              targets: [
                .target(
                  name: "SQL Macro Core",
                  dependencies: [
                    .product(name: "SwiftSyntax", package: "swift-syntax")
                  ]
                ),
                .macro(
                  name: "SQL Macros Implementation",
                  dependencies: [
                    .target(name: "SQL Macro Core"),
                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                  ]
                ),
                .testTarget(
                  name: "SQL Macro Core Tests",
                  dependencies: [.target(name: "SQL Macro Core")]
                ),
              ]
            )
            """
        #expect(Lint.Rule.`macro host only Tests`.findings(manifest).isEmpty)
    }

    @Test
    func `an explicitly named swift syntax package is lawful`() {
        let manifest = """
            let package = Package(
              dependencies: [
                .package(
                  name: "Syntax",
                  url: "https://github.com/swiftlang/swift-syntax.git",
                  from: "603.0.0"
                )
              ],
              targets: [
                .macro(
                  name: "Feature Macros",
                  dependencies: [
                    .product(name: "SwiftSyntax", package: "Syntax")
                  ]
                )
              ]
            )
            """
        #expect(Lint.Rule.`macro host only Tests`.findings(manifest).isEmpty)
    }
}

extension Lint.Rule.`macro host only Tests`.`Edge Case` {
    @Test
    func `similarly named syntax product from another package still fires`() {
        let manifest = """
            let package = Package(
              targets: [
                .macro(
                  name: "Feature Macros",
                  dependencies: [
                    .product(name: "SwiftSyntax", package: "swift-syntax-fork")
                  ]
                )
              ]
            )
            """
        #expect(Lint.Rule.`macro host only Tests`.findings(manifest).count == 1)
    }

    @Test
    func `ordinary library using macro test support is flagged by the manifest approximation`() {
        let manifest = """
            let package = Package(
              targets: [
                .target(
                  name: "Feature Test Support",
                  dependencies: [
                    .product(name: "InlineSnapshotTesting", package: "swift-inline-snapshot-testing"),
                    .product(name: "MacroTesting", package: "swift-macro-testing"),
                  ]
                )
              ]
            )
            """
        #expect(Lint.Rule.`macro host only Tests`.findings(manifest).count == 2)
    }

    @Test
    func `ordinary library using syntax directly is flagged by the manifest approximation`() {
        let manifest = """
            let package = Package(
              targets: [
                .target(
                  name: "Syntax Consumer",
                  dependencies: [
                    .product(name: "SwiftSyntax", package: "swift-syntax")
                  ]
                )
              ]
            )
            """
        #expect(Lint.Rule.`macro host only Tests`.findings(manifest).count == 1)
    }
}
