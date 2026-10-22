public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `leading dot builder statements` = Lint.Rule(
        id: "leading dot builder statements",
        default: .warning,
        controls: [
            .init(
                id: "leading dot builder statements consecutive implicit members",
                source: "route { .post\n.resource(\"greet\") }",
                path: "Sources/HTTP Route/Route.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "leading dot builder statements qualified member",
                source: "route { .post\nHTTP.Target.resource(\"greet\") }",
                path: "Sources/HTTP Route/Route.swift",
                expectation: .clean
            ),
            .init(
                id: "leading dot builder statements explicit boundary",
                source: "route { .post;\n.resource(\"greet\") }",
                path: "Sources/HTTP Route/Route.swift",
                expectation: .clean
            ),
            .init(
                id: "leading dot builder statements comment is not boundary",
                source: "route { .post\n// comment\n.resource(\"greet\") }",
                path: "Sources/HTTP Route/Route.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = IdiomLeadingDotBuilderStatementsVisitor(
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
internal let idiomLeadingDotBuilderStatementsMessage: Swift::String =
    "[leading dot builder statements]: a code-block expression starts with a "
    + "leading-dot implicit member and continues on a later line with another "
    + "dot-prefixed member, which Swift parses as one member chain; qualify the "
    + "later member or insert an explicit expression boundary."

internal func idiomLeadingDotBuilderStatementsHasLineBreak(_ trivia: Trivia) -> Swift::Bool {
    for piece in trivia {
        switch piece {
        case .newlines(let count), .carriageReturns(let count),
            .carriageReturnLineFeeds(let count):
            if count > 0 { return true }
        default:
            continue
        }
    }
    return false
}

internal func idiomLeadingDotBuilderStatementsStartsImplicitly(
    _ expression: ExprSyntax
) -> Swift::Bool {
    if let member = expression.as(MemberAccessExprSyntax.self) {
        guard let base = member.base else { return true }
        return idiomLeadingDotBuilderStatementsStartsImplicitly(base)
    }
    if let call = expression.as(FunctionCallExprSyntax.self) {
        return idiomLeadingDotBuilderStatementsStartsImplicitly(call.calledExpression)
    }
    if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
        return idiomLeadingDotBuilderStatementsStartsImplicitly(specialization.expression)
    }
    if let optionalChain = expression.as(OptionalChainingExprSyntax.self) {
        return idiomLeadingDotBuilderStatementsStartsImplicitly(optionalChain.expression)
    }
    if let forceUnwrap = expression.as(ForceUnwrapExprSyntax.self) {
        return idiomLeadingDotBuilderStatementsStartsImplicitly(forceUnwrap.expression)
    }
    return false
}

internal func idiomLeadingDotBuilderStatementContinuations(
    in expression: ExprSyntax
) -> [TokenSyntax] {
    if let call = expression.as(FunctionCallExprSyntax.self) {
        return idiomLeadingDotBuilderStatementContinuations(in: call.calledExpression)
    }
    if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
        return idiomLeadingDotBuilderStatementContinuations(in: specialization.expression)
    }
    if let optionalChain = expression.as(OptionalChainingExprSyntax.self) {
        return idiomLeadingDotBuilderStatementContinuations(in: optionalChain.expression)
    }
    if let forceUnwrap = expression.as(ForceUnwrapExprSyntax.self) {
        return idiomLeadingDotBuilderStatementContinuations(in: forceUnwrap.expression)
    }
    guard let member = expression.as(MemberAccessExprSyntax.self),
        let base = member.base
    else { return [] }

    var matches = idiomLeadingDotBuilderStatementContinuations(in: base)
    if idiomLeadingDotBuilderStatementsStartsImplicitly(base),
        idiomLeadingDotBuilderStatementsHasLineBreak(member.period.leadingTrivia)
    {
        matches.append(member.period)
    }
    return matches
}

internal final class IdiomLeadingDotBuilderStatementsVisitor: SyntaxVisitor {
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

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        guard let expression = node.item.as(ExprSyntax.self) else { return .visitChildren }
        for period in idiomLeadingDotBuilderStatementContinuations(in: expression) {
            let location = converter.location(for: period.positionAfterSkippingLeadingTrivia)
            matches.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "leading dot builder statements",
                    message: idiomLeadingDotBuilderStatementsMessage
                )
            )
        }
        return .visitChildren
    }
}
