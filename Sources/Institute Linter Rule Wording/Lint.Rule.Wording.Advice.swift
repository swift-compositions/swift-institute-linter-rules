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
        observe: Lint.Rule.measured { source, severity in
            guard wordingAdviceIsInScope(source.file.filePath) else { return [] }
            return wordingAdviceFindings(
                source: source.file,
                text: source.tree.description,
                severity: severity
            )
        }
    )
}

@usableFromInline
internal let wordingAdviceForbidden: [Swift::String] = [
    "advies",
    "advice",
    "you should",
    "we recommend",
]

@usableFromInline
internal let wordingAdviceMessage: Swift::String =
    "[advice wording]: rule-law Swift sources and Localizable.xcstrings "
    + "must not contain the case-insensitive substrings 'advies', 'advice', "
    + "'you should', or 'we recommend'"

internal func wordingAdviceIsInScope(_ path: Swift::String) -> Swift::Bool {
    let components = path.split(separator: "/")
    guard let filename = components.last else { return false }
    if filename == "Localizable.xcstrings" { return true }
    guard filename.hasSuffix(".swift"),
        let ruleLaw = components.firstIndex(of: "rule-law"),
        let sources = components.firstIndex(of: "Sources")
    else { return false }
    return ruleLaw < sources
}

internal func wordingAdviceFindings(
    source: Source.File,
    text: Swift::String,
    severity: Diagnostic.Severity
) -> [Diagnostic.Record] {
    var findings: [Diagnostic.Record] = []
    for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let lowercase = line.lowercased()
        for phrase in wordingAdviceForbidden where lowercase.contains(phrase) {
            findings.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: offset + 1,
                        column: 1
                    ),
                    severity: severity,
                    identifier: "advice wording",
                    message: wordingAdviceMessage
                )
            )
        }
    }
    return findings
}
