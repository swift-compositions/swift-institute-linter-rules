// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-institute-linter-rules open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-institute-linter-rules project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Lint
internal import SwiftSyntax

/// Wave 1 (mechanization-program) — Bool parameter in public-API signature.
///
/// Citation: `[API-IMPL-003]` (code-surface skill — Enum Over Boolean).
///
/// Use enums instead of boolean flags when state can expand. The
/// mechanical signal: a parameter of type `Bool` (or `Swift.Bool`) on
/// a `public` / `open` function or initializer is the lowest-friction
/// indication of the anti-pattern. Boolean parameters in public APIs
/// are particularly painful because they (a) read as call-site
/// noise (`open(create: true, truncate: true, …)`) and (b) cannot
/// extend to a third state without an API break.
extension Lint.Rule {
    public static let `bool public parameter` = Lint.Rule(
        id: "bool public parameter",
        default: .warning,
        controls: [
            .init(
                id: "bool public parameter public bool",
                source: "public func open(create: Bool) {}",
                path: "Sources/Naming Core/PublicBool.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "bool public parameter internal bool",
                source: "func open(create: Bool) {}",
                path: "Sources/Naming Core/InternalBool.swift",
                expectation: .clean
            ),
            .init(
                id: "bool public parameter enum alternative",
                source: "public enum Mode { case create }; public func open(mode: Mode) {}",
                path: "Sources/Naming Core/EnumAlternative.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingBoolParameterVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingBoolParameterMessage: Swift.String =
    "[bool public parameter] [API-IMPL-003]: public function/initializer "
    + "signature has a `Bool` parameter. Use an enum (or named-options "
    + "struct) so additional states can be added without an API break "
    + "and so call sites read as intent (`mode: .strict`) rather than "
    + "magic flags (`strict: true`). `package`-scope and non-public "
    + "declarations are exempt; closure-typed parameters with internal "
    + "Bool arguments are exempt. Memberwise initializers of wire-schema "
    + "types (`Codable`/`Decodable`/`Encodable` conformers whose Bool "
    + "field mirrors a remote provider's schema) and of `Options` "
    + "named-options structs (the rule's own prescribed remedy) are "
    + "exempt per the #16 Option C ledger, Entry II.3."

// Public-or-open-effective check moved to `Naming.hasPublicOrOpenEffective`
// (Lint.Rule.Naming.Shared.swift) — shared with `int public parameter` and
// documented as a cross-pack fix in issue #22.

/// Strips optionals + attributed type wrappers and asks: is the
/// underlying type an identifier `Bool` or `Swift.Bool`?
private func namingBoolParameterIsBoolType(_ type: TypeSyntax) -> Bool {
    var current = type
    while let optional = current.as(OptionalTypeSyntax.self) {
        current = optional.wrappedType
    }
    while let iuo = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        current = iuo.wrappedType
    }
    while let attributed = current.as(AttributedTypeSyntax.self) {
        current = attributed.baseType
    }
    // Also unwrap single-element parenthesised forms (`(Bool)`).
    while let tuple = current.as(TupleTypeSyntax.self), tuple.elements.count == 1 {
        current = tuple.elements.first!.type
    }
    if let identifier = current.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == "Bool"
    }
    if let member = current.as(MemberTypeSyntax.self) {
        // `Swift.Bool`: base is `Swift`, name is `Bool`.
        if member.name.text == "Bool",
            let baseIdentifier = member.baseType.as(IdentifierTypeSyntax.self),
            baseIdentifier.name.text == "Swift"
        {
            return true
        }
    }
    return false
}

internal final class NamingBoolParameterVisitor: SyntaxVisitor {
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

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard Naming.hasPublicOrOpenEffective(Syntax(node), modifiers: node.modifiers) else {
            return .visitChildren
        }
        // Exempt result-builder protocol methods inside an `@resultBuilder`
        // type — `buildExpression(_ expression: Bool)`,
        // `buildPartialBlock(first: Bool)`, etc. take `Bool` because the
        // builder accumulates Bool; the signature is dictated by the
        // builder protocol, not by an [API-IMPL-003] flag choice.
        if Naming.Build.methods.contains(node.name.text),
            Naming.isInsideExtensionPattern(Syntax(node))
        {
            return .visitChildren
        }
        checkParameters(node.signature.parameterClause.parameters)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard Naming.hasPublicOrOpenEffective(Syntax(node), modifiers: node.modifiers) else {
            return .visitChildren
        }
        // Conversion-init exemption: `init(_ x: Bool)` is the Swift-native
        // type-conversion shape (parallel to `init(_ x: Float)` for
        // numeric coercion). The first name is the wildcard `_` and
        // there's exactly one parameter — the call site reads as
        // `Int(true)`, not as a flag. The rule's intent is flag-style
        // public-API parameters, not type conversions.
        let parameters = node.signature.parameterClause.parameters
        if parameters.count == 1,
            let only = parameters.first,
            only.firstName.tokenKind == .wildcard,
            namingBoolParameterIsBoolType(only.type)
        {
            return .visitChildren
        }
        // Memberwise-init exemption (#16 Option C ledger, Entry II.3 DECISION
        // 2026-07-23), two demonstrated false-positive shapes:
        //
        // (a) Wire-schema types: a `Codable`/`Decodable`/`Encodable` conformer
        //     whose Bool stored property mirrors the remote provider's JSON
        //     schema (e.g. Mailgun `Recipient.activated`, GitHub REST
        //     `Invitation.expired`). The Bool is dictated by the wire
        //     contract; an enum remedy would misrepresent it.
        // (b) `Options` named-options structs: the memberwise init of the
        //     named-options struct is the rule's own prescribed remedy
        //     (e.g. `Kernel.File.Copy.Options(overwrite:copyAttributes:)`);
        //     firing on it prescribes recursion into itself.
        //
        // Both exempt ONLY Bool parameters the init assigns memberwise
        // (`self.<param> = <param>`); a behavioral Bool that feeds logic in
        // the same init still fires.
        let wireSchema = namingBoolParameterHasWireSchemaConformance(Syntax(node))
        let optionsStruct = namingBoolParameterEnclosingTypeName(Syntax(node)) == "Options"
        for parameter in parameters {
            guard namingBoolParameterIsBoolType(parameter.type) else { continue }
            if wireSchema || optionsStruct {
                let internalName = parameter.secondName?.text ?? parameter.firstName.text
                if namingBoolParameterAssignsSelf(node.body, parameter: internalName) {
                    continue
                }
            }
            emit(parameter)
        }
        return .visitChildren
    }

    private func checkParameters(_ parameters: FunctionParameterListSyntax) {
        for parameter in parameters {
            guard namingBoolParameterIsBoolType(parameter.type) else {
                continue
            }
            emit(parameter)
        }
    }

    private func emit(_ parameter: FunctionParameterSyntax) {
        let location = converter.location(
            for: parameter.firstName.positionAfterSkippingLeadingTrivia
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
                identifier: "bool public parameter",
                message: namingBoolParameterMessage
            )
        )
    }
}

/// True when the nearest enclosing conformance context of `node` names a
/// wire-schema protocol (`Codable`, `Decodable`, `Encodable`). Uses the
/// pack's `Naming.conformances` walker, which also recovers same-file
/// cross-decl conformances (sibling `extension X: Decodable`).
private func namingBoolParameterHasWireSchemaConformance(_ node: Syntax) -> Bool {
    let wireSchemaLeaves: Swift.Set<Swift.String> = ["Codable", "Decodable", "Encodable"]
    for leaf in Naming.conformances(node) where wireSchemaLeaves.contains(leaf) {
        return true
    }
    return false
}

/// The name of the nearest enclosing nominal type declaration of `node`,
/// or `nil` at file scope / directly inside an extension.
private func namingBoolParameterEnclosingTypeName(_ node: Syntax) -> Swift.String? {
    var current: Syntax? = node.parent
    while let candidate = current {
        if let decl = candidate.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = candidate.as(ClassDeclSyntax.self) { return decl.name.text }
        if let decl = candidate.as(EnumDeclSyntax.self) { return decl.name.text }
        if let decl = candidate.as(ActorDeclSyntax.self) { return decl.name.text }
        if let ext = candidate.as(ExtensionDeclSyntax.self) {
            // `extension Kernel.File.Copy.Options { public init(...) }` — the
            // extended type's leaf is the enclosing nominal name.
            let path = ext.extendedType.trimmedDescription
            if let leaf = path.split(separator: ".").last { return Swift.String(leaf) }
            return path
        }
        current = candidate.parent
    }
    return nil
}

/// True when `body` contains a top-level memberwise assignment
/// `self.<parameter> = <parameter>` for the given internal parameter name.
/// Both the unfolded `SequenceExprSyntax` and folded
/// `InfixOperatorExprSyntax` spellings are recognised.
private func namingBoolParameterAssignsSelf(
    _ body: CodeBlockSyntax?,
    parameter name: Swift.String
) -> Bool {
    guard let body else { return false }
    for item in body.statements {
        if let sequence = item.item.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            if elements.count == 3,
                elements[1].is(AssignmentExprSyntax.self),
                namingBoolParameterIsSelfMember(elements[0], named: name),
                namingBoolParameterIsReference(elements[2], named: name)
            {
                return true
            }
        }
        if let infix = item.item.as(InfixOperatorExprSyntax.self),
            infix.operator.is(AssignmentExprSyntax.self),
            namingBoolParameterIsSelfMember(infix.leftOperand, named: name),
            namingBoolParameterIsReference(infix.rightOperand, named: name)
        {
            return true
        }
    }
    return false
}

private func namingBoolParameterIsSelfMember(_ expr: ExprSyntax, named name: Swift.String) -> Bool {
    guard let member = expr.as(MemberAccessExprSyntax.self),
        member.declName.baseName.text == name,
        let base = member.base?.as(DeclReferenceExprSyntax.self),
        base.baseName.text == "self"
    else { return false }
    return true
}

private func namingBoolParameterIsReference(_ expr: ExprSyntax, named name: Swift.String) -> Bool {
    guard let reference = expr.as(DeclReferenceExprSyntax.self) else { return false }
    return reference.baseName.text == name
}
