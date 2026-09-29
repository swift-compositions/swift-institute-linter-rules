public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `unification typealias` = Lint.Rule(
        id: "unification typealias",
        default: .warning,
        controls: [
            .init(
                id: "unification typealias different leaf",
                source: "public typealias SourceLocation = Text.Location",
                path: "Sources/Naming Core/DifferentLeaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "unification typealias same leaf",
                source: "public typealias Event = Kernel.Event",
                path: "Sources/Naming Core/SameLeaf.swift",
                expectation: .clean
            ),
            .init(
                id: "unification typealias swift bridge",
                source: "public typealias Protocol = Swift.Equatable",
                path: "Sources/Naming Core/SwiftBridge.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingUnificationTypealiasVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingUnificationTypealiasMessage: Swift::String =
    "[unification typealias] [API-NAME-004]: typealias renames a "
    + "member type to a different local name. Type unification MUST use the "
    + "canonical type at all call sites; a typealias bridge adds indirection "
    + "without domain value."

internal final class NamingUnificationTypealiasVisitor: SyntaxVisitor {
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

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let lhsName = node.name.text
        guard let member = node.initializer.value.as(MemberTypeSyntax.self) else {
            return .visitChildren
        }
        if member.genericArgumentClause != nil { return .visitChildren }
        let rhsLeaf = member.name.text
        guard rhsLeaf != lhsName else { return .visitChildren }
        if let baseIdentifier = member.baseType.as(IdentifierTypeSyntax.self),
            baseIdentifier.name.text == "Swift"
        {
            return .visitChildren
        }
        if Naming.isInsideConformingContext(Syntax(node)) {
            return .visitChildren
        }
        if Naming.isProtocolSentinel(rhsLeaf) {
            return .visitChildren
        }
        let location = converter.location(
            for: node.typealiasKeyword.positionAfterSkippingLeadingTrivia
        )
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "unification typealias",
                message: namingUnificationTypealiasMessage
            )
        )
        return .visitChildren
    }
}
