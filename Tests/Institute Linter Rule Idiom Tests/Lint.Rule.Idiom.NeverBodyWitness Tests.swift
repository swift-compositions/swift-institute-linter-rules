import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Idiom

extension Lint.Rule {
    @Suite
    struct `never body witness Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

extension Lint.Rule.`never body witness Tests` {
    static func findings(
        _ source: Swift::String,
        file: Swift::String = "Sources/Parsing Core/Leaf.swift"
    ) -> [Diagnostic.Record] {
        Lint.Rule.`never body witness`
            .observe(Lint.Source.parsed(from: source, file: file), .warning)
            .findings
    }
}

extension Lint.Rule.`never body witness Tests`.Unit {
    @Test
    func `explicit Never body witness in a Core target is flagged`() {
        let findings = Lint.Rule.`never body witness Tests`.findings(
            "struct Leaf: Parsing { var body: Never { fatalError() } }"
        )
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.`never body witness Tests`.`Edge Case` {
    @Test
    func `protocol extension default is admitted`() {
        let findings = Lint.Rule.`never body witness Tests`.findings(
            "extension Parsing where Body == Never { var body: Never { fatalError() } }"
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `qualified Never body witness still fires`() {
        let findings = Lint.Rule.`never body witness Tests`.findings(
            "struct Leaf: Parsing { var body: Swift.Never { fatalError() } }"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `explicit Never body witness outside a Core target is admitted`() {
        let findings = Lint.Rule.`never body witness Tests`.findings(
            "struct Leaf: Parsing { var body: Never { fatalError() } }",
            file: "Sources/Parsing Conformances/Leaf.swift"
        )
        #expect(findings.isEmpty)
    }
}
