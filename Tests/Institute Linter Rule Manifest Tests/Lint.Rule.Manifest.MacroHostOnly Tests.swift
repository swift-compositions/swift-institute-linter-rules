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
}
