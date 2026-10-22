public import Lint

extension Lint.Rule {
    public static let `advice wording` = Lint.Rule(
        id: "advice wording",
        default: .warning,
        controls: [
            .init(
                id: "advice wording violation",
                source: "let result = \"You should apply now.\"",
                path: "rule-law/aow-jaar/Sources/AOW-jaar/Result.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "advice wording lawful result",
                source: "let result = \"Under AOW.Artikel.9.5, the amount is €100.\"",
                path: "rule-law/aow-jaar/Sources/AOW-jaar/Result.swift",
                expectation: .clean
            ),
            .init(
                id: "advice wording near miss",
                source: "let result = \"ADVICE:\\nApply now.\"",
                path: "Apps/Laurie/Sources/Harvest AOW-jaar/Localizable.xcstrings",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { _, _ in [] }
    )
}
