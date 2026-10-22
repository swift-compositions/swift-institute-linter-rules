public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `never body witness` = Lint.Rule(
        id: "never body witness",
        default: .warning,
        controls: [
            .init(
                id: "never body witness explicit property",
                source: "struct Leaf: Parsing { var body: Never { fatalError() } }",
                path: "Sources/Parsing Core/Leaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "never body witness explicit associated type",
                source: "struct Leaf: Parsing { typealias Body = Never }",
                path: "Sources/Parsing Core/Leaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "never body witness protocol default",
                source: "extension Parsing where Body == Never { var body: Never { fatalError() } }",
                path: "Sources/Parsing Core/Parsing.swift",
                expectation: .clean
            ),
            .init(
                id: "never body witness outside Core target",
                source: "struct Leaf: Parsing { var body: Never { fatalError() } }",
                path: "Sources/Parsing Conformances/Leaf.swift",
                expectation: .clean
            ),
            .init(
                id: "never body witness immutable property",
                source: "struct Namespace { let body: Never }",
                path: "Sources/Parsing Core/Namespace.swift",
                expectation: .clean
            ),
            .init(
                id: "never body witness qualified Never",
                source: "struct Leaf: Parsing { var body: Swift.Never { fatalError() } }",
                path: "Sources/Parsing Core/Leaf.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            guard idiomNeverBodyWitnessIsInCoreTarget(source.file.filePath) else { return [] }
            let visitor = IdiomNeverBodyWitnessVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let idiomNeverBodyWitnessMessage: Swift::String =
    "[never body witness] [IDIOM-NEVER-BODY-WITNESS]: a `Sources/* Core` target "
    + "declares an explicit `var body: Never` or `typealias Body = Never` witness. "
    + "Conformer-free Core targets put the `body` default in the protocol extension "
    + "instead of declaring an explicit Never-body witness."

private func idiomNeverBodyWitnessIsInCoreTarget(_ filePath: Swift::String) -> Swift::Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard let sources = components.lastIndex(of: "Sources"), sources + 1 < components.endIndex
    else { return false }
    return components[sources + 1].hasSuffix(" Core")
}

internal final class IdiomNeverBodyWitnessVisitor: SyntaxVisitor {
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

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard
            node.bindingSpecifier.tokenKind == .keyword(.var),
            !node.modifiers.contains(where: { modifier in
                modifier.name.tokenKind == .keyword(.static)
                    || modifier.name.tokenKind == .keyword(.class)
            }),
            idiomNeverBodyWitnessIsTypeMember(Syntax(node))
        else { return .visitChildren }
        for binding in node.bindings {
            guard
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body",
                let type = binding.typeAnnotation?.type,
                idiomIsNever(type),
                !idiomNeverBodyWitnessIsProtocolDefault(Syntax(binding))
            else { continue }
            record(at: binding.pattern.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard
            node.name.text == "Body",
            idiomIsNever(node.initializer.value),
            idiomNeverBodyWitnessIsTypeMember(Syntax(node))
        else { return .visitChildren }
        record(at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    private func record(at position: AbsolutePosition) {
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
                identifier: "never body witness",
                message: idiomNeverBodyWitnessMessage
            )
        )
    }
}

private func idiomNeverBodyWitnessIsTypeMember(_ node: Syntax) -> Swift::Bool {
    var current = node.parent
    while let candidate = current {
        if candidate.is(ProtocolDeclSyntax.self) { return false }
        if candidate.is(StructDeclSyntax.self) || candidate.is(EnumDeclSyntax.self)
            || candidate.is(ClassDeclSyntax.self) || candidate.is(ActorDeclSyntax.self)
            || candidate.is(ExtensionDeclSyntax.self)
        {
            return true
        }
        if candidate.is(FunctionDeclSyntax.self) || candidate.is(InitializerDeclSyntax.self)
            || candidate.is(AccessorDeclSyntax.self) || candidate.is(ClosureExprSyntax.self)
        {
            return false
        }
        current = candidate.parent
    }
    return false
}

private func idiomNeverBodyWitnessIsProtocolDefault(_ node: Syntax) -> Swift::Bool {
    var current = node.parent
    while let candidate = current {
        if let extensionDecl = candidate.as(ExtensionDeclSyntax.self) {
            return extensionDecl.genericWhereClause?.requirements.contains { requirement in
                guard let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self)
                else { return false }
                return (idiomLastTypeName(sameType.leftType) == "Body"
                    && idiomIsNever(sameType.rightType))
                    || (idiomIsNever(sameType.leftType)
                        && idiomLastTypeName(sameType.rightType) == "Body")
            } ?? false
        }
        if candidate.is(StructDeclSyntax.self) || candidate.is(EnumDeclSyntax.self)
            || candidate.is(ClassDeclSyntax.self) || candidate.is(ActorDeclSyntax.self)
            || candidate.is(ProtocolDeclSyntax.self)
        {
            return false
        }
        current = candidate.parent
    }
    return false
}
