import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Manifest

extension Lint.Rule {
    @Suite
    struct `noncopyable protocol shim dependency Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

extension Lint.Rule.`noncopyable protocol shim dependency Tests` {
    static func findings(_ manifest: Swift::String) -> [Diagnostic.Record] {
        Lint.Rule.`noncopyable protocol shim dependency`
            .observe(Lint.Source.parsed(from: manifest, file: "Package.swift"), .warning)
            .findings
    }
}

extension Lint.Rule.`noncopyable protocol shim dependency Tests`.Unit {
    @Test
    func `a noncopyable protocol shim dependency warns`() {
        let findings = Lint.Rule.`noncopyable protocol shim dependency Tests`.findings(
            """
            let package = Package(
                name: "Fixture",
                dependencies: [
                    .package(
                        url: "https://github.com/swift-molecules/swift-equation.git",
                        branch: "main"
                    )
                ]
            )
            """
        )
        #expect(findings.count == 1)
        #expect(findings[0].severity == .warning)
        #expect(
            findings[0].message
                == "[noncopyable protocol shim dependency]: package dependency identity "
                    + "`swift-equation` is one of `swift-equation`, `swift-comparison`, or "
                    + "`swift-hash`; use the corresponding Swift standard-library protocol "
                    + "when only noncopyable protocol support is needed."
        )
    }

    @Test
    func `an unrelated dependency is lawful`() {
        let findings = Lint.Rule.`noncopyable protocol shim dependency Tests`.findings(
            """
            let package = Package(
                name: "Fixture",
                dependencies: [
                    .package(
                        url: "https://github.com/swift-atoms/swift-order.git",
                        branch: "main"
                    )
                ]
            )
            """
        )
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`noncopyable protocol shim dependency Tests`.`Edge Case` {
    @Test
    func `an explicit display name and noncanonical url spelling still warn`() {
        let findings = Lint.Rule.`noncopyable protocol shim dependency Tests`.findings(
            """
            let package = Package(
                name: "Fixture",
                dependencies: [
                    .package(
                        name: "Comparison",
                        url: "https://github.com/Swift-Molecules/Swift-Comparison.git/",
                        branch: "main"
                    )
                ]
            )
            """
        )
        #expect(findings.count == 1)
    }
}
