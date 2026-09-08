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

/// Leaf conformers to `Parser.Protocol` / `Serializer.Protocol` /
/// `Coder.Protocol` MUST declare `public typealias Body = Never`
/// explicitly. Without it, witness-table emission for generic
/// conformers fails at link time with `Undefined symbols ... protocol
/// witness for body.getter`. Citation: `[API-IMPL-020]`.
///
/// Detection is file-scope per conforming type, not per member block:
/// the conformance, the `body` property, and the `Body = Never`
/// typealias may each live in a different declaration site for the
/// same type — a nominal declaration plus one or more extensions in
/// the same file, matching this repository's own one-type-per-file
/// plus split-extension authoring convention. A type is flagged only
/// if NONE of its sites in the file supply `body` or the typealias,
/// at the position of its first conformance-declaring site.
extension Lint.Rule {
    public static let `leaf body typealias missing` = Lint.Rule(
        id: "leaf body typealias missing",
        default: .warning,
        controls: [
            .init(
                id: "leaf body typealias missing Parser",
                source: "extension Example: Parser.`Protocol` {}",
                path: "Sources/Conformance Core/MissingBody.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "leaf body typealias missing Never",
                source: "extension Example: Parser.`Protocol` { public typealias Body = Never }",
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
    + "`Parser.\\`Protocol\\`` / `Serializer.\\`Protocol\\`` / "
    + "`Coder.\\`Protocol\\`` MUST declare `public typealias Body = Never` "
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

    /// The first conformance-declaring site per type key (first
    /// extension/nominal decl in the file whose inheritance clause names
    /// a leaf-body protocol). Only this position is used if the
    /// aggregate verdict for the type fires.
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

    /// Emits one finding per type key that conforms to a leaf-body
    /// protocol somewhere in the file and supplies neither `body` nor
    /// `Body = Never` anywhere in the file. Must be called after `walk`
    /// completes — the verdict is file-scope, not per-declaration-site.
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

/// Returns the trailing name component of `type` — the identifier a
/// nominal declaration's own `name` would carry for the same type,
/// regardless of leading qualification (`Binary.LEB128.Unsigned` and a
/// bare `Unsigned` both key to `"Unsigned"`). Used to correlate a
/// type's own declaration with its extensions within one file.
private func conformanceLeafBodyTypeKey(_ type: TypeSyntax) -> Swift.String {
    if let member = type.as(MemberTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(member.name.text)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(identifier.name.text)
    }
    return type.trimmedDescription
}

/// The trailing path components of every protocol whose conformance
/// triggers the leaf-body-typealias requirement. Pairs are
/// `(host-namespace, protocol-name)` matched against the last two
/// segments of an inherited type's qualified name.
private let leafBodyProtocolPairs: [(host: Swift.String, name: Swift.String)] = [
    ("Parser", "Protocol"),
    ("Serializer", "Protocol"),
    ("Coder", "Protocol"),
]

/// Returns true when any inherited type in `clause` matches one of the
/// leaf-body-protocol pairs. Matching tolerates arbitrary leading
/// module / namespace qualification (e.g.,
/// `Parser_Core.Parser.\`Protocol\``) by inspecting only the
/// trailing two path segments.
private func inheritanceContainsLeafBodyProtocol(_ clause: InheritanceClauseSyntax) -> Swift.Bool {
    for inherited in clause.inheritedTypes {
        if typeMatchesLeafBodyProtocol(inherited.type) {
            return true
        }
    }
    return false
}

/// Returns true when `type` is a `MemberTypeSyntax` whose trailing
/// `(baseTypeName, memberName)` pair (after stripping backticks) matches
/// any entry in `leafBodyProtocolPairs`.
private func typeMatchesLeafBodyProtocol(_ type: TypeSyntax) -> Swift.Bool {
    guard let memberType = type.as(MemberTypeSyntax.self) else { return false }
    let trailingName = Lint.Syntax.Identifier.unescaped(memberType.name.text)
    let baseName: Swift.String
    if let identifier = memberType.baseType.as(IdentifierTypeSyntax.self) {
        baseName = Lint.Syntax.Identifier.unescaped(identifier.name.text)
    } else if let nestedMember = memberType.baseType.as(MemberTypeSyntax.self) {
        baseName = Lint.Syntax.Identifier.unescaped(nestedMember.name.text)
    } else {
        return false
    }
    for pair in leafBodyProtocolPairs where pair.host == baseName && pair.name == trailingName {
        return true
    }
    return false
}

/// Returns true if `block` declares any binding named `body`.
/// Detection covers stored and computed forms; a `body` binding signals
/// the conformer delegates parsing/serialization to a sub-Parser/
/// Serializer body rather than implementing `parse(_:)` /
/// `serialize(_:)` directly.
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

/// Returns true if `block` declares `typealias Body = Never` (or
/// `Swift.Never`). Backticked variants on either side of `=` are
/// tolerated.
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
