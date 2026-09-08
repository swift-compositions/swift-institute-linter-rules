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

/// Stdlib-interop `@_disfavoredOverload` UInt8 forwarders DECLARED AS
/// extensions ON stdlib types (Array, ContiguousArray, ArraySlice, Span,
/// UnsafeBufferPointer, …) MUST live in `* Standard Library Integration`
/// modules, NOT in byte-domain primary modules. Extensions on INSTITUTE
/// types (ArraySlice<Byte>, RFC_*.*, …) that happen to take UInt8 as a
/// stdlib-bridge convenience belong in the primary module and DO NOT
/// fire this rule.
/// Citation: `[API-BYTE-007]`.
extension Lint.Rule {
    public static let `stdlib forwarder outside sli` = Lint.Rule(
        id: "stdlib forwarder outside sli",
        default: .warning,
        controls: [
            .init(
                id: "stdlib forwarder outside sli primary Array",
                source: "extension Array where Element == UInt8 { @_disfavoredOverload public func append(_ value: UInt8) {} }",
                path: "Sources/Binary Core/Forwarder.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "stdlib forwarder outside sli integration Array",
                source: "extension Array where Element == UInt8 { @_disfavoredOverload public func append(_ value: UInt8) {} }",
                path: "Sources/Binary Standard Library Integration/Forwarder.swift",
                expectation: .clean
            ),
            .init(
                id: "stdlib forwarder outside sli institute type",
                source: "extension ArraySlice<Byte> { @_disfavoredOverload public func append(_ value: UInt8) {} }",
                path: "Sources/Binary Core/ByteInputForwarder.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ByteStdlibForwarderOutsideSLIVisitor(
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
internal let byteStdlibForwarderOutsideSLIMessage: Swift.String =
    "[stdlib forwarder outside sli] [API-BYTE-007]: declaration extends "
    + "a stdlib type (Array, ContiguousArray, ArraySlice, Span, "
    + "UnsafeBufferPointer, …), carries `@_disfavoredOverload`, and "
    + "references `UInt8` in its surface, but lives in a byte-domain "
    + "primary module. Stdlib-interop UInt8 forwarders MUST live in the "
    + "package's `* Standard Library Integration` target (the forwarder "
    + "delegates to the `[Byte]`-typed primary via `.lazy.map(Byte.init)` "
    + "or `[Byte](uint8s)`). Move this declaration to a sibling target "
    + "named `<Package> Standard Library Integration`. "
    + "(Extensions on INSTITUTE types with UInt8-accepting "
    + "`@_disfavoredOverload` convenience inits/methods are legitimate "
    + "primary-module surface and do NOT fire this rule.)"

internal final class ByteStdlibForwarderOutsideSLIVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    /// True when the source file's host target is a Standard Library
    /// Integration module — rule does not fire there.
    private let hostIsSLI: Swift.Bool

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        self.hostIsSLI = byteStdlibForwarderHostIsSLI(source.filePath)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !hostIsSLI else { return .visitChildren }
        guard byteStdlibForwarderHasDisfavoredOverload(node.attributes) else {
            return .visitChildren
        }
        let enclosing = byteStdlibForwarderEnclosingExtension(Syntax(node))
        guard let enclosing else { return .visitChildren }
        guard byteStdlibForwarderTypeIsStdlibType(enclosing.extendedType) else {
            return .visitChildren
        }
        if byteStdlibForwarderFunctionMentionsUInt8(node)
            || byteStdlibForwarderExtensionConstraintMentionsUInt8(enclosing)
        {
            emit(at: node.funcKeyword.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !hostIsSLI else { return .visitChildren }
        guard byteStdlibForwarderHasDisfavoredOverload(node.attributes) else {
            return .visitChildren
        }
        let enclosing = byteStdlibForwarderEnclosingExtension(Syntax(node))
        guard let enclosing else { return .visitChildren }
        guard byteStdlibForwarderTypeIsStdlibType(enclosing.extendedType) else {
            return .visitChildren
        }
        if byteStdlibForwarderInitializerMentionsUInt8(node)
            || byteStdlibForwarderExtensionConstraintMentionsUInt8(enclosing)
        {
            emit(at: node.initKeyword.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
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
                identifier: "stdlib forwarder outside sli",
                message: byteStdlibForwarderOutsideSLIMessage
            )
        )
    }
}

/// Returns true when `filePath` indicates the source is in a target whose
/// name ends in `Standard Library Integration`. The host target name is
/// the path component immediately following `Sources/`.
private func byteStdlibForwarderHostIsSLI(_ filePath: Swift.String) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true).map(
        Swift.String.init
    )
    // The target-owning `Sources/` is the LAST one on the path — a checkout
    // root containing an earlier `Sources` component (e.g. a workspace path
    // segment literally named `Sources`) must not steal the anchor.
    for index in components.indices.reversed() where components[index] == "Sources" {
        let targetIndex = components.index(after: index)
        guard targetIndex < components.endIndex else { return false }
        return components[targetIndex].hasSuffix("Standard Library Integration")
    }
    return false
}

private func byteStdlibForwarderHasDisfavoredOverload(
    _ attributes: AttributeListSyntax
)
    -> Swift.Bool
{
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        if attr.attributeName.trimmedDescription == "_disfavoredOverload" {
            return true
        }
    }
    return false
}

private func byteStdlibForwarderFunctionMentionsUInt8(_ node: FunctionDeclSyntax) -> Swift.Bool {
    for parameter in node.signature.parameterClause.parameters {
        if byteStdlibForwarderTypeMentionsUInt8(parameter.type) {
            return true
        }
    }
    if let returnClause = node.signature.returnClause {
        if byteStdlibForwarderTypeMentionsUInt8(returnClause.type) {
            return true
        }
    }
    if let whereClause = node.genericWhereClause {
        if byteStdlibForwarderWhereClauseMentionsUInt8(whereClause) {
            return true
        }
    }
    return false
}

private func byteStdlibForwarderInitializerMentionsUInt8(
    _ node: InitializerDeclSyntax
)
    -> Swift.Bool
{
    for parameter in node.signature.parameterClause.parameters {
        if byteStdlibForwarderTypeMentionsUInt8(parameter.type) {
            return true
        }
    }
    if let whereClause = node.genericWhereClause {
        if byteStdlibForwarderWhereClauseMentionsUInt8(whereClause) {
            return true
        }
    }
    return false
}

private func byteStdlibForwarderWhereClauseMentionsUInt8(
    _ whereClause: GenericWhereClauseSyntax
)
    -> Swift.Bool
{
    for requirement in whereClause.requirements {
        if let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) {
            // leftType and rightType are specialized `SameTypeRequirementSyntax.LeftType` /
            // `.RightType` (not bare `TypeSyntax`) in current SwiftSyntax. Wrap via
            // `Syntax(_:).as(TypeSyntax.self)` so we can re-use the recursive
            // type-mention detector that handles Optional / Array / generic
            // nesting (e.g., `Element == UInt8?`, `Element == [UInt8]`).
            if let rightTS = Syntax(sameType.rightType).as(TypeSyntax.self),
                byteStdlibForwarderTypeMentionsUInt8(rightTS)
            {
                return true
            }
            if let leftTS = Syntax(sameType.leftType).as(TypeSyntax.self),
                byteStdlibForwarderTypeMentionsUInt8(leftTS)
            {
                return true
            }
        }
    }
    return false
}

private func byteStdlibForwarderTypeMentionsUInt8(_ type: TypeSyntax) -> Swift.Bool {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        let leaf = Lint.Syntax.Identifier.unescaped(identifier.name.text)
        if leaf == "UInt8" {
            return true
        }
        if let genericArgs = identifier.genericArgumentClause {
            for arg in genericArgs.arguments {
                if let inner = arg.argument.as(TypeSyntax.self),
                    byteStdlibForwarderTypeMentionsUInt8(inner)
                {
                    return true
                }
            }
        }
        return false
    }
    if let memberType = type.as(MemberTypeSyntax.self) {
        let leaf = Lint.Syntax.Identifier.unescaped(memberType.name.text)
        if leaf == "UInt8" {
            return true
        }
        if let genericArgs = memberType.genericArgumentClause {
            for arg in genericArgs.arguments {
                if let inner = arg.argument.as(TypeSyntax.self),
                    byteStdlibForwarderTypeMentionsUInt8(inner)
                {
                    return true
                }
            }
        }
        return false
    }
    if let arrayType = type.as(ArrayTypeSyntax.self) {
        return byteStdlibForwarderTypeMentionsUInt8(arrayType.element)
    }
    if let dictionaryType = type.as(DictionaryTypeSyntax.self) {
        return byteStdlibForwarderTypeMentionsUInt8(dictionaryType.key)
            || byteStdlibForwarderTypeMentionsUInt8(dictionaryType.value)
    }
    if let optionalType = type.as(OptionalTypeSyntax.self) {
        return byteStdlibForwarderTypeMentionsUInt8(optionalType.wrappedType)
    }
    if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return byteStdlibForwarderTypeMentionsUInt8(implicitlyUnwrapped.wrappedType)
    }
    if let attributedType = type.as(AttributedTypeSyntax.self) {
        return byteStdlibForwarderTypeMentionsUInt8(attributedType.baseType)
    }
    if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) {
        return byteStdlibForwarderTypeMentionsUInt8(someOrAny.constraint)
    }
    if let tupleType = type.as(TupleTypeSyntax.self) {
        for element in tupleType.elements
        where byteStdlibForwarderTypeMentionsUInt8(element.type) {
            return true
        }
        return false
    }
    if let functionType = type.as(FunctionTypeSyntax.self) {
        for parameter in functionType.parameters
        where byteStdlibForwarderTypeMentionsUInt8(parameter.type) {
            return true
        }
        return byteStdlibForwarderTypeMentionsUInt8(functionType.returnClause.type)
    }
    return false
}

/// Curated set of stdlib type leaf-names whose extensions are the
/// canonical home for `@_disfavoredOverload` UInt8 forwarders. The rule
/// fires only when the enclosing extension's extended type's leaf-name
/// matches one of these (or the extended type is explicitly
/// `Swift.<X>`).
///
/// Note on `Array`: included even though `Array.Array` shadows
/// `Swift.Array` in the institute. The institute convention is to write
/// `extension Swift.Array` when the stdlib type is intended; bare
/// `extension Array` in a file that resolves `Array` to institute is
/// arguably misnamed and the rule will fire — that is acceptable, since
/// the in-file shadow ambiguity is itself a hygiene issue independently
/// flagged at the qualification level.
private let byteStdlibForwarderStdlibTypeLeafNames: Swift.Set<Swift.String> = [
    "Array",
    "ContiguousArray",
    "ArraySlice",
    "Sequence",
    "Collection",
    "RangeReplaceableCollection",
    "BidirectionalCollection",
    "RandomAccessCollection",
    "MutableCollection",
    "Span",
    "MutableSpan",
    "RawSpan",
    "OutputSpan",
    "OutputRawSpan",
    "UnsafeBufferPointer",
    "UnsafeMutableBufferPointer",
    "UnsafeRawBufferPointer",
    "UnsafeMutableRawBufferPointer",
    "UnsafePointer",
    "UnsafeMutablePointer",
    "UnsafeRawPointer",
    "UnsafeMutableRawPointer",
    "String",
    "Substring",
    "StringProtocol",
    "Dictionary",
    "Set",
    "Range",
    "ClosedRange",
    "Optional",
    "Result",
]

/// Walks parent nodes from `node` up to the nearest `ExtensionDeclSyntax`
/// and returns it. Returns `nil` when the declaration is not inside an
/// extension (top-level / inside a struct or class body).
private func byteStdlibForwarderEnclosingExtension(_ node: Syntax) -> ExtensionDeclSyntax? {
    var current: Syntax? = node.parent
    while let parent = current {
        if let extensionDecl = parent.as(ExtensionDeclSyntax.self) {
            return extensionDecl
        }
        current = parent.parent
    }
    return nil
}

/// Returns true when the extension carries a `where`-clause constraint
/// mentioning `UInt8` (e.g., `extension Array where Element == UInt8`).
/// This is how [API-BYTE-003]'s canonical 6-forwarder allowlist
/// expresses byte-interop constraints on stdlib-collection extensions.
private func byteStdlibForwarderExtensionConstraintMentionsUInt8(
    _ ext: ExtensionDeclSyntax
)
    -> Swift.Bool
{
    if let whereClause = ext.genericWhereClause,
        byteStdlibForwarderWhereClauseMentionsUInt8(whereClause)
    {
        return true
    }
    // Also check generic arguments on the extendedType itself, e.g.
    // `extension ContiguousArray<UInt8> { ... }`.
    return byteStdlibForwarderTypeMentionsUInt8(ext.extendedType)
}

/// `Swift.<X>` is always stdlib. Otherwise check the type's leaf-name
/// against the curated allowlist. Strips backticks before comparison.
private func byteStdlibForwarderTypeIsStdlibType(_ type: TypeSyntax) -> Swift.Bool {
    // `Swift.<X>` — explicit module qualifier means stdlib.
    if let memberType = type.as(MemberTypeSyntax.self) {
        if let baseIdentifier = memberType.baseType.as(IdentifierTypeSyntax.self),
            Lint.Syntax.Identifier.unescaped(baseIdentifier.name.text) == "Swift"
        {
            return true
        }
        // Multi-segment nested type (e.g., `ArraySlice<Byte>`, `RFC_4122.UUID`):
        // an institute / domain-nested type. Not stdlib.
        return false
    }
    // Bare identifier — check leaf-name against the allowlist.
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        let leaf = Lint.Syntax.Identifier.unescaped(identifier.name.text)
        return byteStdlibForwarderStdlibTypeLeafNames.contains(leaf)
    }
    return false
}
