import Lint
import Linter_Rules_Test_Support
import SwiftParser
import Testing

@testable import Institute_Linter_Rule_Wording

extension Lint.Rule {
    @Suite
    struct `advice wording Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`advice wording Tests` {
    static func findings(
        in source: Swift::String,
        file: Swift::String
    ) -> [Diagnostic.Record] {
        Lint.Rule.`advice wording`
            .observe(Lint.Source.parsed(from: source, file: file), .warning)
            .findings
    }
}

extension Lint.Rule.`advice wording Tests`.Unit {
    @Test
    func `advice wording in a rule law source is flagged`() {
        let findings = Lint.Rule.`advice wording Tests`.findings(
            in: "let result = \"You should apply now.\"",
            file: "/workspace/rule-law/aow-jaar/Sources/AOW-jaar/Result.swift"
        )
        #expect(findings.count == 1)
        #expect(findings.first?.severity == .warning)
    }

    @Test
    func `statute result wording is lawful`() {
        let findings = Lint.Rule.`advice wording Tests`.findings(
            in: "let result = \"Under AOW.Artikel.9.5, the amount is €100.\"",
            file: "/workspace/rule-law/aow-jaar/Sources/AOW-jaar/Result.swift"
        )
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`advice wording Tests`.`Edge Case` {
    @Test
    func `uppercase advice in Localizable remains a violation`() {
        let findings = Lint.Rule.`advice wording Tests`.findings(
            in: """
                {
                  "strings": {
                    "result": { "comment": "ADVICE: apply now" }
                  }
                }
                """,
            file: "/workspace/Apps/Laurie/Sources/Harvest AOW-jaar/Localizable.xcstrings"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `the four forbidden substrings are case insensitive`() {
        let findings = Lint.Rule.`advice wording Tests`.findings(
            in: """
                let dutch = "ADVIES"
                let english = "Advice"
                let direction = "YOU SHOULD apply"
                let recommendation = "We Recommend applying"
                """,
            file: "/workspace/rule-law/aow-jaar/Sources/AOW-jaar/Wording.swift"
        )
        #expect(findings.count == 4)
    }

    @Test
    func `ordinary Swift sources outside rule law are out of scope`() {
        let findings = Lint.Rule.`advice wording Tests`.findings(
            in: "let advice = \"You should apply now.\"",
            file: "/workspace/swift-example/Sources/Example/Example.swift"
        )
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`advice wording Tests`.Integration {
    @Test
    func `message states the complete predicate`() {
        let findings = Lint.Rule.`advice wording Tests`.findings(
            in: "let result = \"we recommend applying\"",
            file: "/workspace/rule-law/aow-jaar/Sources/AOW-jaar/Result.swift"
        )
        #expect(
            findings.first?.message
                == "[advice wording]: rule-law Swift sources and Localizable.xcstrings must not contain the case-insensitive substrings 'advies', 'advice', 'you should', or 'we recommend'"
        )
    }
}
