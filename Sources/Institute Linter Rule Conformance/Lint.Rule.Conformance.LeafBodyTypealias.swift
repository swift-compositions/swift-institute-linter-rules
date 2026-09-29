public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `leaf body typealias missing` = Lint.Rule(
        id: "leaf body typealias missing",
        default: .warning,
        controls: [
            .init(
                id: "leaf body typealias missing Parser",
                source: "extension Example: Parsing {}",
                path: "Sources/Conformance Core/MissingBody.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "leaf body typealias missing Never",
                source: "extension Example: Parsing { public typealias Body = Never }",
                path: "Sources/Conformance Core/NeverBody.swift",
                expectation: .clean
            ),
            .init(
                id: "leaf body typealias missing Sendable",
                source: "extension Example: Sendable {}",
                path: "Sources/Conformance Core/Sendable.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ConformanceLeafBodyTypealiasVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            visitor.finalizeMatches()
            return visitor.matches
        }
    )
}

@usableFromInline
internal let conformanceLeafBodyTypealiasMessage: Swift.String =
    "[leaf body typealias missing] [API-IMPL-020]: leaf conformer to "
    + "`Parsing` / `Serializing` / "
    + "`Coding` MUST declare `public typealias Body = Never` "
    + "explicitly. Generic leaf conformers without it fail at link time "
    + "with `Undefined symbols ... protocol witness for body.getter`; "
    + "non-generic leaf conformers SHOULD include it as the minimum-safe "
    + "pattern. Add `public typealias Body = Never` next to the other "
    + "associatedtype typealiases in the conformance."

internal final class ConformanceLeafBodyTypealiasVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    private var conformanceSite: [Swift.String: AbsolutePosition] = [:]
    private var typesWithBodyProperty: Swift.Set<Swift.String> = []
    private var typesWithBodyNeverTypealias: Swift.Set<Swift.String> = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func record(
        key: Swift.String,
        inheritance: InheritanceClauseSyntax?,
        memberBlock: MemberBlockSyntax,
        keywordPosition: AbsolutePosition
    ) {
        if let inheritance, inheritanceContainsLeafBodyProtocol(inheritance) {
            if conformanceSite[key] == nil {
                conformanceSite[key] = keywordPosition
            }
        }
        if memberBlockHasBodyProperty(memberBlock) {
            typesWithBodyProperty.insert(key)
        }
        if memberBlockHasBodyNeverTypealias(memberBlock) {
            typesWithBodyNeverTypealias.insert(key)
        }
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            key: conformanceLeafBodyTypeKey(node.extendedType),
            inheritance: node.inheritanceClause,
            memberBlock: node.memberBlock,
            keywordPosition: node.extensionKeyword.positionAfterSkippingLeadingTrivia
        )
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            key: Lint.Syntax.Identifier.unescaped(node.name.text),
            inheritance: node.inheritanceClause,
            memberBlock: node.memberBlock,
            keywordPosition: node.structKeyword.positionAfterSkippingLeadingTrivia
        )
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            key: Lint.Syntax.Identifier.unescaped(node.name.text),
            inheritance: node.inheritanceClause,
            memberBlock: node.memberBlock,
            keywordPosition: node.classKeyword.positionAfterSkippingLeadingTrivia
        )
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            key: Lint.Syntax.Identifier.unescaped(node.name.text),
            inheritance: node.inheritanceClause,
            memberBlock: node.memberBlock,
            keywordPosition: node.enumKeyword.positionAfterSkippingLeadingTrivia
        )
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            key: Lint.Syntax.Identifier.unescaped(node.name.text),
            inheritance: node.inheritanceClause,
            memberBlock: node.memberBlock,
            keywordPosition: node.actorKeyword.positionAfterSkippingLeadingTrivia
        )
        return .visitChildren
    }

    func finalizeMatches() {
        for (key, position) in conformanceSite.sorted(by: {
            $0.value.utf8Offset < $1.value.utf8Offset
        }) {
            if typesWithBodyProperty.contains(key) || typesWithBodyNeverTypealias.contains(key) {
                continue
            }
            emit(at: position)
        }
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
                identifier: "leaf body typealias missing",
                message: conformanceLeafBodyTypealiasMessage
            )
        )
    }
}

private func conformanceLeafBodyTypeKey(_ type: TypeSyntax) -> Swift.String {
    if let member = type.as(MemberTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(member.name.text)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(identifier.name.text)
    }
    return type.trimmedDescription
}

private let leafBodyProtocolNames: Swift.Set<Swift.String> = ["Parsing", "Serializing", "Coding"]

private func inheritanceContainsLeafBodyProtocol(_ clause: InheritanceClauseSyntax) -> Swift.Bool {
    clause.inheritedTypes.contains { typeMatchesLeafBodyProtocol($0.type) }
}

private func typeMatchesLeafBodyProtocol(_ type: TypeSyntax) -> Swift.Bool {
    let name: Swift.String? =
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            Lint.Syntax.Identifier.unescaped(identifier.name.text)
        } else if let member = type.as(MemberTypeSyntax.self) {
            Lint.Syntax.Identifier.unescaped(member.name.text)
        } else {
            nil
        }
    return name.map(leafBodyProtocolNames.contains) ?? false
}

private func memberBlockHasBodyProperty(_ block: MemberBlockSyntax) -> Swift.Bool {
    for member in block.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
        for binding in variable.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            if Lint.Syntax.Identifier.unescaped(pattern.identifier.text) == "body" {
                return true
            }
        }
    }
    return false
}

private func memberBlockHasBodyNeverTypealias(_ block: MemberBlockSyntax) -> Swift.Bool {
    for member in block.members {
        guard let typealiasDecl = member.decl.as(TypeAliasDeclSyntax.self) else { continue }
        guard Lint.Syntax.Identifier.unescaped(typealiasDecl.name.text) == "Body" else { continue }
        let value = typealiasDecl.initializer.value
        if let identifier = value.as(IdentifierTypeSyntax.self) {
            if Lint.Syntax.Identifier.unescaped(identifier.name.text) == "Never" {
                return true
            }
        }
        if let memberType = value.as(MemberTypeSyntax.self) {
            if Lint.Syntax.Identifier.unescaped(memberType.name.text) == "Never" {
                return true
            }
        }
    }
    return false
}
