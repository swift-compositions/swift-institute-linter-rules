public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `fatal error outside tests` = Lint.Rule(
        id: "fatal error outside tests",
        default: .warning,
        controls: [
            .init(
                id: "fatal error outside tests source",
                source: "func f() -> Never { fatalError(\"unreachable\") }",
                path: "Sources/Idiom Consumer/Trap.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fatal error outside tests qualified",
                source: "func f() -> Never { Swift.fatalError() }",
                path: "Sources/Idiom Consumer/Trap.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fatal error outside tests test",
                source: "func f() -> Never { fatalError(\"unreachable\") }",
                path: "Tests/Idiom Consumer Tests/Trap.swift",
                expectation: .clean
            ),
            .init(
                id: "fatal error outside tests parsing leaf witness",
                source: "struct Leaf: Parsing { var body: Never { fatalError(\"leaf\") } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .clean
            ),
            .init(
                id: "fatal error outside tests qualified generic coding leaf witness",
                source: "extension Example { struct Coder: Library.Utility.Coding<Int, Failure> { var body: Never { borrowing get { return fatalError(\"leaf\") } } } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .clean
            ),
            .init(
                id: "fatal error outside tests same-file conforming extension",
                source: "struct Leaf {}\nextension Leaf: Serializing { var body: Swift.Never { get { fatalError() } } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .clean
            ),
            .init(
                id: "fatal error outside tests nonconforming never body",
                source: "struct Leaf { var body: Never { fatalError() } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fatal error outside tests leaf body of another type",
                source: "struct Leaf: Parsing { var body: Int { fatalError() } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fatal error outside tests leaf never property not named body",
                source: "struct Leaf: Parsing { var other: Never { fatalError() } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fatal error outside tests leaf never body with more statements",
                source: "struct Leaf: Parsing { var body: Never { log(); fatalError() } }",
                path: "Sources/Idiom Consumer/Leaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fatal error outside tests member",
                source: "func f() { logger.fatalError(\"message\") }",
                path: "Sources/Idiom Consumer/Log.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let path = source.file.filePath
            guard path.hasPrefix("Sources/") || path.contains("/Sources/") else {
                return []
            }
            let conformances = IdiomLeafConformanceCollector(viewMode: .sourceAccurate)
            conformances.walk(source.tree)
            let visitor = IdiomFatalErrorOutsideTestsVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter,
                conformingTypes: conformances.conformingTypes
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

@usableFromInline
internal let idiomFatalErrorOutsideTestsMessage: Swift::String =
    "[fatal error outside tests] [SOURCE-FATAL-ERROR]: `fatalError` traps the "
    + "process; library and executable sources model the failure as a typed "
    + "error or make the state unrepresentable. `fatalError` is admitted only "
    + "in tests and fixtures."

internal final class IdiomFatalErrorOutsideTestsVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    let conformingTypes: Swift::Set<Swift::String>
    var matches: [Diagnostic.Record] = []

    init(
        source: Source.File,
        severity: Diagnostic.Severity,
        converter: SourceLocationConverter,
        conformingTypes: Swift::Set<Swift::String>
    ) {
        self.source = source
        self.severity = severity
        self.converter = converter
        self.conformingTypes = conformingTypes
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let isFatalError: Swift::Bool =
            if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) {
                reference.baseName.text == "fatalError"
            } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
                member.declName.baseName.text == "fatalError"
                    && member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Swift"
            } else {
                false
            }
        guard isFatalError, !isRequiredNeverBodyWitness(node) else { return .visitChildren }
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "fatal error outside tests",
                message: idiomFatalErrorOutsideTestsMessage
            )
        )
        return .visitChildren
    }

    private func isRequiredNeverBodyWitness(_ node: FunctionCallExprSyntax) -> Swift::Bool {
        let statement: Syntax? =
            if let returned = node.parent?.as(ReturnStmtSyntax.self) {
                Syntax(returned)
            } else {
                Syntax(node)
            }
        guard let item = statement?.parent?.as(CodeBlockItemSyntax.self),
            let items = item.parent?.as(CodeBlockItemListSyntax.self),
            items.count == 1
        else { return false }
        let block: AccessorBlockSyntax? =
            if let block = items.parent?.as(AccessorBlockSyntax.self) {
                block
            } else if let body = items.parent?.as(CodeBlockSyntax.self),
                let accessor = body.parent?.as(AccessorDeclSyntax.self),
                accessor.accessorSpecifier.tokenKind == .keyword(.get),
                let list = accessor.parent?.as(AccessorDeclListSyntax.self),
                list.count == 1
            {
                list.parent?.as(AccessorBlockSyntax.self)
            } else {
                nil
            }
        guard let binding = block?.parent?.as(PatternBindingSyntax.self),
            binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body",
            let type = binding.typeAnnotation?.type,
            idiomIsNever(type)
        else { return false }
        return idiomEnclosingLeafConformer(of: Syntax(binding), conformingTypes: conformingTypes)
    }
}

internal let idiomLeafProtocols: Swift::Set<Swift::String> = ["Parsing", "Serializing", "Coding"]

internal func idiomLastTypeName(_ type: TypeSyntax) -> Swift::String? {
    if let member = type.as(MemberTypeSyntax.self) {
        member.name.text
    } else if let identifier = type.as(IdentifierTypeSyntax.self) {
        identifier.name.text
    } else {
        nil
    }
}

internal func idiomInheritsLeafProtocol(_ clause: InheritanceClauseSyntax?) -> Swift::Bool {
    clause?.inheritedTypes.contains { idiomLastTypeName($0.type).map(idiomLeafProtocols.contains) ?? false } ?? false
}

internal func idiomIsNever(_ type: TypeSyntax) -> Swift::Bool {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        identifier.name.text == "Never"
            && (identifier.moduleSelector.map { $0.moduleName.text == "Swift" } ?? true)
    } else if let member = type.as(MemberTypeSyntax.self) {
        member.name.text == "Never"
            && member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
    } else {
        false
    }
}

internal func idiomEnclosingLeafConformer(
    of node: Syntax,
    conformingTypes: Swift::Set<Swift::String>
) -> Swift::Bool {
    var current = node.parent
    while let candidate = current {
        if let decl = candidate.as(StructDeclSyntax.self) {
            return idiomInheritsLeafProtocol(decl.inheritanceClause) || conformingTypes.contains(decl.name.text)
        }
        if let decl = candidate.as(EnumDeclSyntax.self) {
            return idiomInheritsLeafProtocol(decl.inheritanceClause) || conformingTypes.contains(decl.name.text)
        }
        if let decl = candidate.as(ClassDeclSyntax.self) {
            return idiomInheritsLeafProtocol(decl.inheritanceClause) || conformingTypes.contains(decl.name.text)
        }
        if let decl = candidate.as(ExtensionDeclSyntax.self) {
            return idiomInheritsLeafProtocol(decl.inheritanceClause)
                || idiomLastTypeName(decl.extendedType).map(conformingTypes.contains) ?? false
        }
        current = candidate.parent
    }
    return false
}

internal final class IdiomLeafConformanceCollector: SyntaxVisitor {
    var conformingTypes: Swift::Set<Swift::String> = []

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if idiomInheritsLeafProtocol(node.inheritanceClause), let name = idiomLastTypeName(node.extendedType) {
            conformingTypes.insert(name)
        }
        return .visitChildren
    }
}
