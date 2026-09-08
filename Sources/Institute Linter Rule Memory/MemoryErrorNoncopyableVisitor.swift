internal import Lint
internal import SwiftSyntax

internal final class MemoryErrorNoncopyableVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    let extensionConformances: [Swift.String: Swift.Set<Swift.String>]
    var matches: [Diagnostic.Record] = []

    init(
        source: Source.File,
        severity: Diagnostic.Severity,
        converter: SourceLocationConverter,
        extensionConformances: [Swift.String: Swift.Set<Swift.String>]
    ) {
        self.source = source
        self.severity = severity
        self.converter = converter
        self.extensionConformances = extensionConformances
        super.init(viewMode: .sourceAccurate)
    }

    private func conformsToError(
        name: TokenSyntax,
        inheritanceClause: InheritanceClauseSyntax?
    ) -> Bool {
        if let inheritanceClause {
            for inherited in inheritanceClause.inheritedTypes {
                var current = inherited.type
                while let attributed = current.as(AttributedTypeSyntax.self) {
                    current = attributed.baseType
                }
                // Base-blind fix (#25 defect 5 point 3): a `MemberTypeSyntax`
                // leaf named `Error` must be rooted at the bare `Swift` module,
                // or a nested non-stdlib `Module.Error` false-positives.
                if let identifier = current.as(IdentifierTypeSyntax.self),
                    identifier.name.text == "Error"
                {
                    return true
                }
                if let member = current.as(MemberTypeSyntax.self),
                    member.name.text == "Error",
                    let base = member.baseType.as(IdentifierTypeSyntax.self),
                    base.name.text == "Swift"
                {
                    return true
                }
            }
        }
        if extensionConformances[name.text]?.contains("Error") == true {
            return true
        }
        return false
    }

    private func suppressesCopyable(_ inheritanceClause: InheritanceClauseSyntax) -> Bool {
        for inherited in inheritanceClause.inheritedTypes {
            if let suppressed = inherited.type.as(SuppressedTypeSyntax.self) {
                let typeName = suppressed.type.trimmedDescription
                if typeName == "Copyable" || typeName.hasSuffix(".Copyable") {
                    return true
                }
            }
        }
        return false
    }

    private func check(name: TokenSyntax, inheritanceClause: InheritanceClauseSyntax?) {
        guard conformsToError(name: name, inheritanceClause: inheritanceClause) else { return }
        // `~Copyable` can only be suppressed on the primary declaration's
        // own clause — an extension cannot re-suppress a conformance.
        guard let inheritanceClause, suppressesCopyable(inheritanceClause) else { return }
        let location = converter.location(for: name.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "noncopyable error",
                message: memoryErrorNoncopyableMessage
            )
        )
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        check(name: node.name, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        check(name: node.name, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        check(name: node.name, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        // `protocol Failure: Error, ~Copyable {}` is the same [MEM-COPY-002]
        // violation in the same single-clause shape (#25 defect 5).
        check(name: node.name, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }
}
