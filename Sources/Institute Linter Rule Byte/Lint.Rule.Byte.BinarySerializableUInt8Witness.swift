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

/// `Binary.Serializable` / `Binary.Parseable` (and sibling-family
/// protocols like `Binary.ASCII.Serializable`) witness implementations
/// MUST use `Buffer.Element == Byte` (or `Source.Element == Byte`),
/// NOT `== UInt8`. The protocol surface was retyped to `Byte` at
/// `swift-binary@b121c0e` (Wave 2 of the broader L2/L3 byte-
/// typing gap arc). The only legitimate `Buffer.Element == UInt8` shapes
/// are the explicit `@_disfavoredOverload` stdlib-interop forwarders
/// allowlisted in the W2 6-forwarder set; consumer-side witnesses MUST
/// retype.
/// Citation: `[API-BYTE-003]`.
extension Lint.Rule {
    public static let `binary serializable uint8 witness` = Lint.Rule(
        id: "binary serializable uint8 witness",
        default: .error,
        controls: [
            .init(
                id: "binary serializable uint8 witness UInt8",
                source: "extension Foo: Binary.Serializable { public static func "
                    + "serialize<Buffer: RangeReplaceableCollection>(_ value: Self, into buffer: inout Buffer) where Buffer.Element == UInt8 {} }",
                path: "Sources/Byte Core/UInt8Witness.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "binary serializable uint8 witness Byte",
                source: "extension Foo: Binary.Serializable { public static func "
                    + "serialize<Buffer: RangeReplaceableCollection>(_ value: Self, into buffer: inout Buffer) where Buffer.Element == Byte {} }",
                path: "Sources/Byte Core/ByteWitness.swift",
                expectation: .clean
            ),
            .init(
                id: "binary serializable uint8 witness outside context",
                source: "extension Array { public static func serialize<Buffer: RangeReplaceableCollection>(_ value: Self, into buffer: inout Buffer) where Buffer.Element == UInt8 {} }",
                path: "Sources/Byte Core/OutsideWitness.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ByteBinarySerializableUInt8WitnessVisitor(
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
internal let byteBinarySerializableUInt8WitnessMessage: Swift.String =
    "[binary serializable uint8 witness] [API-BYTE-003]: `Binary."
    + "Serializable` / `Binary.Parseable` witness uses `Buffer.Element == "
    + "UInt8` (or `Source.Element == UInt8`). The protocol surface is now "
    + "Byte-typed (Wave 2, swift-binary@b121c0e). Retype the "
    + "where-clause to `== Byte`. If this is a stdlib-interop forwarder, "
    + "add `@_disfavoredOverload` per [API-BYTE-006]."

/// Sibling-family protocols whose witness signatures take `Buffer.Element`
/// / `Source.Element` / `Bytes.Element` typed parameters. Detection on
/// the extension's inheritance clause; leaf-segment match per
/// [API-IMPL-020] convention.
private let byteSerializableLikeProtocolPairs: [(host: Swift.String, name: Swift.String)] = [
    ("Binary", "Serializable"),
    ("Binary", "Parseable"),
]

/// Witness associated-type names whose `== UInt8` constraint is what
/// the rule flags. Constraint shape is `<TypeParam>.Element == UInt8`.
private let byteWitnessElementTypeParameterNames: Swift.Set<Swift.String> = [
    "Buffer",
    "Bytes",
    "Source",
    "Sequence",
    "Collection",
]

internal final class ByteBinarySerializableUInt8WitnessVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    /// Stack of "inside a Binary.Serializable / Binary.Parseable
    /// extension" markers. We push on entering a qualifying extension and
    /// pop on leaving so the gate reflects only the innermost enclosing
    /// extension. (Swift extensions cannot themselves nest, so this isn't
    /// guarding against a nested-extension false positive; it's what keeps
    /// a later, non-qualifying extension on the same or a different type
    /// from inheriting a `true` left on the stack by an earlier one.)
    private var contextStack: [Swift.Bool] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let isQualifying = extensionConformsToSerializableLike(node)
        contextStack.append(isQualifying)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        if !contextStack.isEmpty {
            contextStack.removeLast()
        }
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard contextStack.last == true else { return .visitChildren }
        let baseName = Lint.Syntax.Identifier.unescaped(node.name.text)
        guard byteWitnessFunctionNames.contains(baseName) else { return .visitChildren }
        if byteFunctionHasDisfavoredOverload(node.attributes) {
            return .visitChildren
        }
        guard let whereClause = node.genericWhereClause else { return .visitChildren }
        for requirement in whereClause.requirements {
            if byteRequirementIsElementEqualsUInt8(requirement) {
                emit(at: requirement.positionAfterSkippingLeadingTrivia)
                return .visitChildren
            }
        }
        return .visitChildren
    }

    // `"init"` is listed in `byteWitnessFunctionNames`, but an initializer
    // witness (`Binary.Parseable`'s `init(parsing:)`) is an
    // `InitializerDeclSyntax`, not a `FunctionDeclSyntax` — its keyword is
    // `initKeyword`, not a `name` token, so the `FunctionDeclSyntax`
    // visitor above can never reach it. Without this visitor, "init" in
    // the set is unreachable and initializer witnesses go unchecked at
    // `.error` severity.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard contextStack.last == true else { return .visitChildren }
        if byteFunctionHasDisfavoredOverload(node.attributes) {
            return .visitChildren
        }
        guard let whereClause = node.genericWhereClause else { return .visitChildren }
        for requirement in whereClause.requirements {
            if byteRequirementIsElementEqualsUInt8(requirement) {
                emit(at: requirement.positionAfterSkippingLeadingTrivia)
                return .visitChildren
            }
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
                identifier: "binary serializable uint8 witness",
                message: byteBinarySerializableUInt8WitnessMessage
            )
        )
    }
}

/// Witness function names the rule inspects for Element-equals-UInt8
/// where-clauses.
internal let byteWitnessFunctionNames: Swift.Set<Swift.String> = [
    "serialize",
    "parse",
    "init",
]

/// Returns true when the extension hosts witness implementations for a
/// Binary serializable-like protocol — either via the **conformer-extension
/// shape** (inheritance clause names `Binary.Serializable` /
/// `Binary.Parseable`, e.g. `extension Foo: Binary.Serializable { ... }`)
/// OR via the **default-impl-extension shape** (extended type IS the
/// protocol, e.g. `extension Binary.Serializable { ... }` or
/// `extension Binary.Serializable where Self: ... { ... }`).
///
/// Both shapes host witness implementations: per-conformer impls in the
/// first shape, default impls (for any conformer without an override) in
/// the second. The skill's `[API-BYTE-003]` Statement covers both —
/// "witness implementations MUST use `Buffer.Element == Byte`"; the gate
/// accepts either path. Matching tolerates leaf-segment-only via
/// `MemberTypeSyntax`.
///
/// Coverage extension landed 2026-05-20 (Arc G Phase 7 addendum) per
/// the L2/L3 byte-typing gap plan note
/// § "Post-W2 Arc G".
internal func extensionConformsToSerializableLike(_ node: ExtensionDeclSyntax) -> Swift.Bool {
    // Path 1 — conformer-extension shape: inheritance clause names the protocol.
    if let inheritance = node.inheritanceClause {
        for inherited in inheritance.inheritedTypes {
            if byteTypeMatchesSerializableLike(inherited.type) {
                return true
            }
        }
    }
    // Path 2 — default-impl-extension shape: extended type IS the protocol.
    if byteTypeMatchesSerializableLike(node.extendedType) {
        return true
    }
    return false
}

private func byteTypeMatchesSerializableLike(_ type: TypeSyntax) -> Swift.Bool {
    guard let memberType = type.as(MemberTypeSyntax.self) else { return false }
    let trailingName = Lint.Syntax.Identifier.unescaped(memberType.name.text)
    // Walk to the OUTERMOST root identifier, not just the immediate parent
    // leaf — `Binary.ASCII.Serializable`'s immediate base leaf is `ASCII`,
    // but the family's host is `Binary`. `byteSerializableLikeProtocolPairs`
    // matches on (host, trailing-name), so the root must be resolved all
    // the way down regardless of how many interior segments a sibling-
    // family spelling carries.
    guard let rootName = byteRootIdentifierName(memberType.baseType) else { return false }
    for pair in byteSerializableLikeProtocolPairs
    where pair.host == rootName && pair.name == trailingName {
        return true
    }
    return false
}

/// Returns the outermost root identifier's (backtick-stripped) name for
/// a possibly multi-segment qualified type, e.g. `Binary` for
/// `Binary.ASCII.Serializable`'s base `Binary.ASCII`.
private func byteRootIdentifierName(_ type: TypeSyntax) -> Swift.String? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(identifier.name.text)
    }
    if let memberType = type.as(MemberTypeSyntax.self) {
        return byteRootIdentifierName(memberType.baseType)
    }
    return nil
}

/// Returns true if a function carries `@_disfavoredOverload`.
internal func byteFunctionHasDisfavoredOverload(_ attributes: AttributeListSyntax) -> Swift.Bool {
    for element in attributes {
        guard let attribute = element.as(AttributeSyntax.self) else { continue }
        guard let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
            continue
        }
        if Lint.Syntax.Identifier.unescaped(identifier.name.text) == "_disfavoredOverload" {
            return true
        }
    }
    return false
}

/// Returns true for `where <TypeParam>.Element == UInt8` shapes.
private func byteRequirementIsElementEqualsUInt8(
    _ requirement: GenericRequirementSyntax
)
    -> Swift.Bool
{
    guard let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) else {
        return false
    }
    let left = sameType.leftType.trimmedDescription
    let right = sameType.rightType.trimmedDescription
    // LHS: `<TypeParam>.Element` where TypeParam is in the recognized set.
    let leftIsElement: Swift.Bool = {
        let parts = left.split(separator: ".")
        guard parts.count == 2 else { return false }
        guard Lint.Syntax.Identifier.unescaped(Swift.String(parts[1])) == "Element" else {
            return false
        }
        return byteWitnessElementTypeParameterNames.contains(
            Lint.Syntax.Identifier.unescaped(Swift.String(parts[0]))
        )
    }()
    guard leftIsElement else { return false }
    // RHS: `UInt8` or `Swift.UInt8`.
    return right == "UInt8" || right == "Swift.UInt8"
}
