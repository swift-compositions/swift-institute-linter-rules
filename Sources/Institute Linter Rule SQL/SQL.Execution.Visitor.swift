internal import Lint
internal import SwiftSyntax

extension SQL.Execution {
    internal final class Visitor: SyntaxVisitor {
        private let source: Source.File
        private let severity: Diagnostic.Severity
        private let converter: SourceLocationConverter
        internal var matches: [Diagnostic.Record] = []

        internal init(
            source: Source.File,
            severity: Diagnostic.Severity,
            converter: SourceLocationConverter
        ) {
            self.source = source
            self.severity = severity
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(
            _ node: FunctionCallExprSyntax
        ) -> SyntaxVisitorContinueKind {
            guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                sqlExecutionNames.contains(member.declName.baseName.text)
            else { return .visitChildren }
            let location = converter.location(for: member.declName.positionAfterSkippingLeadingTrivia)
            matches.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "sql execution in library target",
                    message: sqlExecutionInLibraryTargetMessage
                )
            )
            return .visitChildren
        }
    }
}

private let sqlExecutionNames: Swift::Set<Swift::String> = [
    "execute", "fetchAll", "fetchCount", "fetchOne", "fetchSet",
]
