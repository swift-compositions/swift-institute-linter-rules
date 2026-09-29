public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `existential parameter` = Lint.Rule(
        id: "existential parameter",
        default: .warning,
        controls: [
            .init(
                id: "existential parameter any protocol",
                source: "func render(_ view: any View) {}",
                path: "Sources/Idiom Consumer/Render.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "existential parameter generic",
                source: "func render(_ view: some View) {}",
                path: "Sources/Idiom Consumer/Render.swift",
                expectation: .clean
            ),
            .init(
                id: "existential parameter any error",
                source: "func report(_ error: any Error) {}",
                path: "Sources/Idiom Consumer/Report.swift",
                expectation: .clean
            ),
            .init(
                id: "existential parameter test",
                source: "func render(_ view: any View) {}",
                path: "Tests/Idiom Consumer Tests/Render.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let path = source.file.filePath
            guard path.hasPrefix("Sources/") || path.contains("/Sources/") else {
                return []
            }
            let visitor = IdiomExistentialParameterVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

@usableFromInline
internal let idiomExistentialParameterMessage: Swift.String =
    "[existential parameter] [SOURCE-EXISTENTIAL-PARAMETER]: a parameter typed "
    + "`any P` boxes its argument and erases its type; take `some P` or a "
    + "generic parameter instead. `any Error` is admitted."

internal final class IdiomExistentialParameterVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        let finder = IdiomExistentialParameterFinder(viewMode: .sourceAccurate)
        finder.walk(node.type)
        for position in finder.positions {
            let location = converter.location(for: position)
            matches.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "existential parameter",
                    message: idiomExistentialParameterMessage
                )
            )
        }
        return .visitChildren
    }
}

internal final class IdiomExistentialParameterFinder: SyntaxVisitor {
    var positions: [AbsolutePosition] = []

    override func visit(_ node: SomeOrAnyTypeSyntax) -> SyntaxVisitorContinueKind {
        let constraint = node.constraint.trimmedDescription
        if node.someOrAnySpecifier.tokenKind == .keyword(.any),
            constraint != "Error", constraint != "Swift.Error", constraint != "Swift::Error"
        {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionTypeSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
