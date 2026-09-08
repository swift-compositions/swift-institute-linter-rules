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

/// Flags a `` `Protocol` ``-sentinel member nested (via `extension
/// <Carrier> { … }`) under a carrier type that a public GENERIC
/// top-level `typealias` fronts — the shape ruled unsupported by
/// `swift-institute/.github#122` (disposition c, 2026-07-30):
/// member-type lookup through an unbound-generic-alias base never
/// resolves the nested member on any toolchain
/// (`swift-institute/Issues#81`), so `FrontDoor<T>.Protocol` ships a
/// public surface with no way to spell it.
///
/// Three historical instances existed (`Set`, `Array`, and `Tree`
/// primitives, each pairing a public `typealias Name<T> = __Name<T>`
/// front door with a nested `` `Protocol` `` alias declared in an
/// extension of the underscored `__Name`); doctrine (W6 of the ruling)
/// records the retirement and the exclusion going forward. This rule
/// mechanizes W7: detect the SHAPE — a generic front-door typealias
/// plus a same-carrier extension nesting the sentinel — not the three
/// retired names.
///
/// AST shape (both pieces must appear in the SAME file — this engine
/// has no whole-package member index, so cross-file front-door /
/// extension pairs are outside what a per-file syntax rule can
/// correlate; the common authoring shape keeps both in one file, and
/// this is the mechanically checkable subset):
///
/// 1. A `public`/`open` `typealias Name<T, …> = Carrier<T, …>` — the
///    typealias's OWN generic parameter clause is what makes it a
///    front door (not merely an alias for a concrete type).
/// 2. An `extension Carrier { … }` (the RHS's base identifier, NOT
///    the front-door alias's own name) declaring a nested type member
///    (`typealias`/`struct`/`enum`/`class`/`protocol`) named the
///    `Protocol` sentinel — bare `Protocol` or backtick-escaped
///    `` `Protocol` `` (both spellings signal the hoisted-protocol
///    pattern per [API-IMPL-009] / [PKG-NAME-001]).
///
/// Reference NON-firing shape (`swift-storage`,
/// `Store` vs `Storage<Allocation>`): `Store` is a bare, non-generic
/// enum namespace with its own directly-nested `` `Protocol` ``
/// member — there is no separate generic front-door typealias
/// pointing AT `Store`, so member lookup on `Store.\`Protocol\``
/// resolves normally and this rule does not fire. `Storage<Allocation>`
/// is a real generic struct (not a typealias target) that deliberately
/// carries NO nested `Protocol` sentinel at all — Allocation-independent
/// capability surfaces are hoisted to non-generic homes instead,
/// exactly to avoid this failure mode.
///
/// ADVISORY at introduction, per the standing graduation discipline
/// (issue #11) — promote to `.error` only after fleet validation.
extension Lint.Rule {
    /// Flags a `` `Protocol` `` sentinel nested under a carrier fronted by a public generic top-level typealias — member lookup through the alias never resolves it ([swift-institute/.github#122], disposition c).
    public static let `protocol sentinel under generic front door` = Lint.Rule(
        id: "protocol sentinel under generic front door",
        default: .warning,
        controls: [
            .init(
                id: "protocol sentinel under generic front door generic alias",
                source: "public typealias Array<Element> = __Array<Element>\n"
                    + "extension __Array { typealias `Protocol` = __ArrayProtocol }",
                path: "Sources/Structure Core/Array.Protocol.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "protocol sentinel under generic front door nominal carrier",
                source: "public struct Store {}\n"
                    + "extension Store { typealias `Protocol` = StoreProtocol }",
                path: "Sources/Structure Core/Store.Protocol.swift",
                expectation: .clean
            ),
            .init(
                id: "protocol sentinel under generic front door different carrier",
                source: "public typealias Array<Element> = __Array<Element>\n"
                    + "extension Store { typealias `Protocol` = StoreProtocol }",
                path: "Sources/Structure Core/Store.Protocol.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = StructureProtocolSentinelUnderGenericFrontDoorVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.resolvedMatches()
        }
    )
}

private let structureProtocolSentinelUnderGenericFrontDoorMessage: Swift.String =
    "[protocol sentinel under generic front door]: this `Protocol` "
    + "sentinel is nested under a carrier that a public GENERIC "
    + "top-level `typealias` fronts. Member-type lookup through an "
    + "unbound-generic-alias base never resolves a nested member on any "
    + "toolchain (swift-institute/Issues#81), so the front door's "
    + "consumer-facing spelling (`FrontDoor<T>.Protocol`) has no way to "
    + "reach this member — ruled unsupported in "
    + "swift-institute/.github#122 (disposition c). Hoist the protocol "
    + "to a non-generic top-level name instead (the `Store`/"
    + "`Storage<Allocation>` precedent in swift-storage), "
    + "retaining a non-generic compatibility alias if needed."

internal final class StructureProtocolSentinelUnderGenericFrontDoorVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    private var matches: [Diagnostic.Record] = []

    /// Carrier leaf name (the RHS base identifier) -> true once a public
    /// generic front-door typealias targeting it is found anywhere in
    /// the file.
    private var frontDoorCarrierNames: Swift.Set<Swift.String> = []

    private struct Candidate {
        let carrierName: Swift.String
        let position: AbsolutePosition
    }
    private var candidates: [Candidate] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.genericParameterClause != nil else { return .visitChildren }
        guard psgfdHasPublicOrOpen(node.modifiers) else { return .visitChildren }
        if let carrierName = psgfdLeafIdentifierName(node.initializer.value) {
            frontDoorCarrierNames.insert(carrierName)
        }
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let carrierName = psgfdLeafIdentifierName(node.extendedType) else {
            return .visitChildren
        }
        for member in node.memberBlock.members {
            guard let position = psgfdProtocolSentinelPosition(member.decl) else { continue }
            candidates.append(Candidate(carrierName: carrierName, position: position))
        }
        return .visitChildren
    }

    /// Cross-references collected `` `Protocol` ``-sentinel candidates
    /// against the (possibly later-in-file) set of generic front-door
    /// carrier names.
    internal func resolvedMatches() -> [Diagnostic.Record] {
        for candidate in candidates {
            guard frontDoorCarrierNames.contains(candidate.carrierName) else { continue }
            let location = converter.location(for: candidate.position)
            matches.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "protocol sentinel under generic front door",
                    message: structureProtocolSentinelUnderGenericFrontDoorMessage
                )
            )
        }
        return matches
    }
}

// MARK: - Free helpers

private func psgfdHasPublicOrOpen(_ modifiers: DeclModifierListSyntax) -> Swift.Bool {
    for modifier in modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public), .keyword(.open): return true
        default: continue
        }
    }
    return false
}

/// The leaf identifier name of `type`'s base — unwraps a
/// `MemberTypeSyntax`'s trailing segment or an `IdentifierTypeSyntax`,
/// ignoring any generic-argument clause. `nil` for shapes with no
/// single resolvable identifier (tuples, function types, etc.).
private func psgfdLeafIdentifierName(_ type: TypeSyntax) -> Swift.String? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(identifier.name.text)
    }
    if let member = type.as(MemberTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(member.name.text)
    }
    return nil
}

/// If `decl` is a nested type-like member (`typealias`/`struct`/
/// `enum`/`class`/`protocol`) named the `Protocol` sentinel, returns
/// its name token's position; otherwise `nil`.
private func psgfdProtocolSentinelPosition(_ decl: DeclSyntax) -> AbsolutePosition? {
    if let typealiasDecl = decl.as(TypeAliasDeclSyntax.self),
        structureIsProtocolSentinelName(typealiasDecl.name.text)
    {
        return typealiasDecl.name.positionAfterSkippingLeadingTrivia
    }
    if let structDecl = decl.as(StructDeclSyntax.self),
        structureIsProtocolSentinelName(structDecl.name.text)
    {
        return structDecl.name.positionAfterSkippingLeadingTrivia
    }
    if let enumDecl = decl.as(EnumDeclSyntax.self),
        structureIsProtocolSentinelName(enumDecl.name.text)
    {
        return enumDecl.name.positionAfterSkippingLeadingTrivia
    }
    if let classDecl = decl.as(ClassDeclSyntax.self),
        structureIsProtocolSentinelName(classDecl.name.text)
    {
        return classDecl.name.positionAfterSkippingLeadingTrivia
    }
    if let protocolDecl = decl.as(ProtocolDeclSyntax.self),
        structureIsProtocolSentinelName(protocolDecl.name.text)
    {
        return protocolDecl.name.positionAfterSkippingLeadingTrivia
    }
    return nil
}
