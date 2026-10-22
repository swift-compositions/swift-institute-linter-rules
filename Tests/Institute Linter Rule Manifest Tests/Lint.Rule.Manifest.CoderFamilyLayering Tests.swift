import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Manifest

extension Lint.Rule {
    @Suite
    struct `coder family layering Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`coder family layering Tests` {
    static func findings(_ manifest: Swift::String) -> [Diagnostic.Record] {
        Lint.Rule.`coder family layering`
            .observe(Lint.Source.parsed(from: manifest, file: "Package.swift"), .warning)
            .findings
    }

    static func manifest(
        package: Swift::String,
        dependency: Swift::String,
        product: Swift::String? = nil
    ) -> Swift::String {
        let productDependency = product.map {
            ", targets: [.target(name: \"Fixture\", dependencies: [.product(name: \"\($0)\", package: \"\(dependency)\")])]"
        } ?? ""
        return "let package = Package(name: \"\(package)\", dependencies: ["
            + ".package(url: \"https://github.com/swift-molecules/\(dependency).git\", branch: \"main\")]"
            + productDependency + ")"
    }
}

extension Lint.Rule.`coder family layering Tests`.Unit {
    @Test
    func `coder package rejects the parser atom`() {
        let findings = Lint.Rule.`coder family layering Tests`.findings(
            Lint.Rule.`coder family layering Tests`.manifest(
                package: "swift-json-coder",
                dependency: "swift-parser"
            )
        )
        #expect(findings.count == 1)
        #expect(findings[0].severity == .warning)
        #expect(
            findings[0].message
                == "[coder family layering]: `swift-json-coder` may depend only on `swift-coder`, `swift-json`, `swift-json-parser`, and `swift-json-serializer`; found `swift-parser`."
        )
    }

    @Test
    func `coder package accepts coder and its own family`() {
        let dependencies = [
            "swift-coder",
            "swift-json",
            "swift-json-parser",
            "swift-json-serializer",
        ]
        for dependency in dependencies {
            let findings = Lint.Rule.`coder family layering Tests`.findings(
                Lint.Rule.`coder family layering Tests`.manifest(
                    package: "swift-json-coder",
                    dependency: dependency
                )
            )
            #expect(findings.isEmpty)
        }
    }
}

extension Lint.Rule.`coder family layering Tests`.`Edge Case` {
    @Test
    func `similarly named parser dependency remains a violation`() {
        let findings = Lint.Rule.`coder family layering Tests`.findings(
            Lint.Rule.`coder family layering Tests`.manifest(
                package: "swift-json-coder",
                dependency: "swift-json-parser-support"
            )
        )
        #expect(findings.count == 1)
    }

    @Test
    func `ordinary packages are exempt`() {
        let findings = Lint.Rule.`coder family layering Tests`.findings(
            Lint.Rule.`coder family layering Tests`.manifest(
                package: "swift-json",
                dependency: "swift-parser"
            )
        )
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`coder family layering Tests`.Integration {
    @Test
    func `parser package rejects serializer products`() {
        let findings = Lint.Rule.`coder family layering Tests`.findings(
            Lint.Rule.`coder family layering Tests`.manifest(
                package: "swift-json-parser",
                dependency: "swift-coder",
                product: "Serializer"
            )
        )
        #expect(findings.count == 1)
        #expect(
            findings[0].message
                == "[coder family layering]: `swift-json-parser` must not depend on serializer packages or products; found product `Serializer` from `swift-coder`."
        )
    }

    @Test
    func `rfc domain package rejects wire coding dependencies`() {
        let findings = Lint.Rule.`coder family layering Tests`.findings(
            Lint.Rule.`coder family layering Tests`.manifest(
                package: "swift-rfc-9112",
                dependency: "swift-parser"
            )
        )
        #expect(findings.count == 1)
        #expect(
            findings[0].message
                == "[coder family layering]: `swift-rfc-9112` must keep parsing and serializing dependencies and targets in its `swift-rfc-9112-coder` sibling; found dependency `swift-parser`."
        )
    }
}
