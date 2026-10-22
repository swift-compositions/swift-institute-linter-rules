public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `raw sql statement` = Lint.Rule(
        id: "raw sql statement",
        default: .warning,
        controls: [
            .init(
                id: "raw sql statement macro",
                source: "let query = #sql(\"SELECT * FROM records\")",
                path: "Sources/Database/Query.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "raw sql statement migration history",
                source: "try database.execute(sql: \"CREATE TABLE records (id INTEGER)\")",
                path: "Sources/Database/Migrations/001_CreateRecords.swift",
                expectation: .clean
            ),
            .init(
                id: "raw sql statement typed query",
                source: "let query = Record.select(Record.Columns.id)",
                path: "Sources/Database/Query.swift",
                expectation: .clean
            ),
            .init(
                id: "raw sql statement qualified request near miss",
                source: "let request = GRDB.SQLRequest<Row>(sql: \"  select * FROM records\")",
                path: "Sources/Database/Query.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            guard idiomRawSQLIsApplicationSource(source.file.filePath) else { return [] }
            let visitor = IdiomRawSQLStatementVisitor(
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
internal let idiomRawSQLStatementMessage: Swift::String =
    "[raw sql statement] [DATABASE-RAW-SQL]: `#sql`, a `sql:` argument, "
    + "`SQLRequest`, or `Row.fetch*` contains a string literal whose first "
    + "SQL token is SELECT, INSERT, UPDATE, DELETE, CREATE, or PRAGMA in a "
    + "`Sources` path outside a `Migrations` path; use swift-sql/swift-sqlite "
    + "typed query construction. Frozen `Sources/**/Migrations/**` history is exempt."

internal let idiomRawSQLStatementKeywords: Swift::Set<Swift::String> = [
    "CREATE", "DELETE", "INSERT", "PRAGMA", "SELECT", "UPDATE",
]

internal func idiomRawSQLIsApplicationSource(_ path: Swift::String) -> Swift::Bool {
    let components = path.split(separator: "/")
    return components.contains("Sources") && !components.contains("Migrations")
}

internal func idiomRawSQLLeadingText(_ literal: StringLiteralExprSyntax) -> Swift::String {
    var result = ""
    for segment in literal.segments {
        guard let text = segment.as(StringSegmentSyntax.self) else { break }
        result += text.content.text
    }
    return result
}

internal func idiomRawSQLIsWholeStatement(_ literal: StringLiteralExprSyntax) -> Swift::Bool {
    let text = idiomRawSQLLeadingText(literal)
    let trimmed = text.drop(while: { $0.isWhitespace })
    let token = Swift::String(trimmed.prefix(while: { $0.isLetter }))
    return idiomRawSQLStatementKeywords.contains(token.uppercased())
}

internal func idiomRawSQLExpressionName(_ expression: ExprSyntax) -> Swift::String? {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
        return member.declName.baseName.text
    }
    if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
        return idiomRawSQLExpressionName(specialization.expression)
    }
    return nil
}

internal func idiomRawSQLIsRowFetch(_ expression: ExprSyntax) -> Swift::Bool {
    guard let member = expression.as(MemberAccessExprSyntax.self),
        member.declName.baseName.text.hasPrefix("fetch"),
        let base = member.base
    else { return false }
    return idiomRawSQLExpressionName(base) == "Row"
}

internal func idiomRawSQLStatementLiteral(
    in arguments: LabeledExprListSyntax
) -> StringLiteralExprSyntax? {
    arguments.lazy
        .compactMap { $0.expression.as(StringLiteralExprSyntax.self) }
        .first(where: idiomRawSQLIsWholeStatement)
}

internal final class IdiomRawSQLStatementVisitor: SyntaxVisitor {
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

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.macroName.text == "sql",
            idiomRawSQLStatementLiteral(in: node.arguments) != nil
        else { return .visitChildren }
        emit(at: node.positionAfterSkippingLeadingTrivia)
        return .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let name = idiomRawSQLExpressionName(node.calledExpression)
        let hasSQLArgument = node.arguments.contains { argument in
            argument.label?.text == "sql"
                && argument.expression.as(StringLiteralExprSyntax.self).map(
                    idiomRawSQLIsWholeStatement
                ) == true
        }
        let isSQLRequest = name == "SQLRequest"
        let isRowFetch = idiomRawSQLIsRowFetch(node.calledExpression)
        guard (hasSQLArgument || isSQLRequest || isRowFetch),
            idiomRawSQLStatementLiteral(in: node.arguments) != nil
        else { return .visitChildren }
        emit(at: node.positionAfterSkippingLeadingTrivia)
        return .skipChildren
    }

    private func emit(at position: AbsolutePosition) {
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
                identifier: "raw sql statement",
                message: idiomRawSQLStatementMessage
            )
        )
    }
}
