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

/// Wave 2b finalization (2026-05-10) — extensions on `~Copyable`-aware
/// generic types MUST include explicit `where ... ~Copyable`
/// constraints.
///
/// Citation: `[MEM-COPY-004]` (memory-safety skill, the ownership note).
///
/// Without an explicit `where Element: ~Copyable` clause, an extension
/// is implicitly constrained to `where Element: Copyable` — silently
/// shrinking the surface to copyable elements only. The institute
/// pattern adds explicit `~Copyable` constraints for any extension
/// that should apply to noncopyable element types.
extension Lint.Rule {
    public static let `extension noncopyable constraint` = Lint.Rule(
        id: "extension noncopyable constraint",
        default: .warning,
        controls: [
            .init(
                id: "extension noncopyable constraint missing",
                source: "extension Container<Element> { consuming func transfer() {} }",
                path: "Sources/Memory Core/MissingNoncopyableConstraint.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "extension noncopyable constraint explicit",
                source: "extension Container where Element: ~Copyable { consuming func transfer() {} }",
                path: "Sources/Memory Core/ExplicitNoncopyableConstraint.swift",
                expectation: .clean
            ),
            .init(
                id: "extension noncopyable constraint no ownership",
                source: "extension Container<Element> { func describe() -> String { \"\" } }",
                path: "Sources/Memory Core/NoOwnershipSurface.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = MemoryExtensionNoncopyableConstraintVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

/// Stdlib generic types whose generic parameter is language-bounded to
/// `Copyable` — writing `where ... ~Copyable` against these types is
/// rejected at type-check, so the rule's request is impossible to
/// satisfy. These types ARE generic (they take a generic parameter), so
/// the syntactic non-generic detection does NOT skip them when the user
/// writes the explicit-parameter form `extension Array<Element>`. The
/// allowlist covers the explicit-parameter case.
///
/// (Non-generic institute types — Comparison, Equation, Hash, Ordinal,
/// Cardinal, Affine.Discrete.Vector, Lint.Source.Parsed, and any future
/// directly-`~Copyable` type — are handled by
/// `extensionTargetIsSyntacticallyNonGeneric(_:)` below, NOT by allowlist
/// entries. Adding allowlist entries for non-generic types would be
/// redundant maintenance.)
@usableFromInline
internal let memoryExtensionConstraintInexpressibleTypes: Swift.Set<Swift.String> = [
    "UnsafePointer",
    "UnsafeMutablePointer",
    "UnsafeRawPointer",
    "UnsafeMutableRawPointer",
    "UnsafeBufferPointer",
    "UnsafeMutableBufferPointer",
    "Array",
    "ArraySlice",
    "ContiguousArray",
    "CollectionOfOne",
    "EmptyCollection",
    "KeyValuePairs",
    "ReversedCollection",
    "Range",
    "ClosedRange",
    "PartialRangeFrom",
    "PartialRangeThrough",
    "PartialRangeUpTo",
    "Optional",
    "Dictionary",
    "Set",
    "String",
    "Substring",
    "Result",
]

/// Reserved, currently-empty hook for a future qualified-path allowlist
/// (#25 nit: this set is empty and the lookup at its one call site can
/// therefore never succeed — it is dead code today, not an active
/// allowlist. Previously documented as a populated curated allowlist,
/// which contradicted the "Currently empty" comment in the body; this
/// doc block now states the honest, current status instead of
/// reasoning about entries that don't exist).
///
/// If syntactic non-generic detection
/// (`extensionTargetIsSyntacticallyNonGeneric(_:)`) is ever found
/// insufficient for a qualified path whose leaf name is shared by a
/// generic type elsewhere in the ecosystem, this is the place to add
/// that qualified path, matched against the extension target's full
/// dotted path (e.g. `Affine.Discrete.Vector`). No such case is known
/// to exist today.
@usableFromInline
internal let memoryExtensionConstraintInexpressibleQualifiedTypes: Swift.Set<Swift.String> = []

@usableFromInline
internal let memoryExtensionNoncopyableConstraintMessage: Swift.String =
    "[extension noncopyable constraint] [MEM-COPY-004]: extensions on `~Copyable`-"
    + "aware generic types MUST include explicit `where ... ~Copyable` constraints. "
    + "Without it, the extension is implicitly `where Element: Copyable` and the "
    + "surface silently shrinks. Add `where Element: ~Copyable` (or the matching "
    + "constraint name for your type's generic parameter)."

internal final class MemoryExtensionNoncopyableConstraintVisitor: SyntaxVisitor {
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

    private func extendedTypeLeafName(_ type: TypeSyntax) -> Swift.String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }

    private func extendedTypeQualifiedName(_ type: TypeSyntax) -> Swift.String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            guard let base = extendedTypeQualifiedName(member.baseType) else {
                return nil
            }
            return "\(base).\(member.name.text)"
        }
        return nil
    }

    /// Detects whether the extension's target carries any syntactic
    /// generic-parameter marker. Returns `true` when the extension is
    /// against a type that is syntactically non-generic (no `<...>` at
    /// any segment of the extended type AND no generic where clause on
    /// the extension itself).
    ///
    /// The rule's premise — "extension on a `~Copyable`-aware generic
    /// type implicitly constrains to Copyable when no `where ...
    /// ~Copyable` clause is given, silently shrinking the surface" —
    /// only applies when the extension target IS generic. For
    /// syntactically-non-generic targets, the where clause is structurally
    /// inexpressible (no generic parameter exists to constrain), so the
    /// rule's request is vacuous and the rule MUST NOT fire.
    ///
    /// Examples of syntactically-non-generic forms (correctly skipped):
    ///
    /// ```swift
    /// extension Comparison { consuming func ... }            // bare leaf
    /// extension Affine.Discrete.Vector { ... }               // qualified non-generic
    /// extension Lint.Source.Parsed { borrowing func ... }    // qualified non-generic
    /// ```
    ///
    /// Examples of syntactically-generic forms (correctly visited):
    ///
    /// ```swift
    /// extension Container<Element> { consuming func ... }    // explicit `<Element>`
    /// extension Container where Element: Sendable { ... }    // explicit where clause
    /// ```
    ///
    /// **Known limitation — the implicit-generic-target false negative**:
    /// when an author writes `extension SomeGenericType { ... }` without
    /// `<T>` and without a where clause, this detection treats it as
    /// non-generic and skips. The detection is wrong if `SomeGenericType`
    /// IS generic. The trade-off vs. the prior allowlist-only approach:
    ///
    /// - Allowlist-only: every new directly-`~Copyable` type required a
    ///   per-entry allowlist add (Lint.Source.Parsed, future `~Copyable`
    ///   types) → ongoing maintenance burden.
    /// - Syntactic detection: false negatives on implicit-parameter
    ///   extensions of generic types (rare per institute conventions
    ///   which encourage explicit `<T>` or `where T:` forms) → zero
    ///   ongoing maintenance.
    ///
    /// Institute conventions strongly favor explicit generic parameter
    /// declaration; the false-negative risk is bounded.
    private func extensionTargetIsSyntacticallyNonGeneric(_ node: ExtensionDeclSyntax) -> Bool {
        if extendedTypeHasGenericArguments(node.extendedType) {
            return false
        }
        if node.genericWhereClause != nil {
            return false
        }
        return true
    }

    /// Recursively checks whether any segment of the extended-type
    /// expression carries a `<...>` generic argument clause.
    private func extendedTypeHasGenericArguments(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.genericArgumentClause != nil
        }
        if let member = type.as(MemberTypeSyntax.self) {
            if member.genericArgumentClause != nil {
                return true
            }
            return extendedTypeHasGenericArguments(member.baseType)
        }
        return false
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Filename-pattern exemption: `* where *.swift` files use the
        // [API-IMPL-007] where-clause-discriminator naming convention.
        // The author has enumerated quadrants via filenames; absence of
        // a constraint in any one quadrant file is deliberate within
        // the family. The rule's warning structurally inverts the
        // author's intent here.
        if source.filePath.contains(" where ") {
            return .visitChildren
        }
        // Syntactic non-generic exemption: the rule's premise applies
        // only to generic types whose where clause could silently shrink
        // to Copyable. For syntactically-non-generic targets, no generic
        // parameter exists to constrain — the rule's request is vacuous.
        // This subsumes prior per-type allowlist entries for non-generic
        // institute types (Comparison, Equation, Hash, Ordinal, Cardinal,
        // Affine.Discrete.Vector) and scales automatically to new
        // directly-`~Copyable` types (Lint.Source.Parsed and successors).
        // See `extensionTargetIsSyntacticallyNonGeneric(_:)` for the
        // false-negative trade-off documentation.
        if extensionTargetIsSyntacticallyNonGeneric(node) {
            return .visitChildren
        }
        // Constraint-inexpressible exemption for syntactically-generic
        // targets whose generic parameter is language-bounded to Copyable.
        // Specifically catches `extension Array<Element>` (and the wider
        // stdlib generic-Copyable-bounded family) where the user wrote
        // the explicit generic-parameter form, so syntactic-non-generic
        // detection didn't fire. The qualified-name lookup runs first;
        // the leaf lookup remains for unambiguous stdlib leaves.
        if let qualified = extendedTypeQualifiedName(node.extendedType),
            memoryExtensionConstraintInexpressibleQualifiedTypes.contains(qualified)
        {
            return .visitChildren
        }
        if let leaf = extendedTypeLeafName(node.extendedType),
            memoryExtensionConstraintInexpressibleTypes.contains(leaf)
        {
            return .visitChildren
        }
        // Walk the extension body for ownership signals.
        let finder = MemoryExtensionNoncopyableOwnershipFinder(viewMode: .sourceAccurate)
        finder.walk(node.memberBlock)
        guard finder.found else {
            return .visitChildren
        }
        // Parameter-pack exemption: `~Copyable each T` is not language-
        // expressible in Swift 6.x. If the extension uses pack syntax
        // anywhere (where clause, body signatures, generic constraints),
        // the where clause the rule asks for cannot be written.
        let packFinder = MemoryExtensionPackExpansionFinder(viewMode: .sourceAccurate)
        packFinder.walk(node)
        guard !packFinder.found else {
            return .visitChildren
        }
        guard !memoryWhereClauseHasNoncopyable(node.genericWhereClause) else {
            return .visitChildren
        }
        // Exempt per [RULE-EXEMPT-1] (positive-Copyable): author has
        // explicitly scoped to a Copyable surface; the rule's "silent
        // shrink" premise is inverted by the explicit conformance.
        // Helper lives in `Lint.Rule.Memory.Shared.swift`.
        guard !memoryWhereClauseHasPositiveCopyable(node.genericWhereClause) else {
            return .visitChildren
        }
        let location = converter.location(for: node.extendedType.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "extension noncopyable constraint",
                message: memoryExtensionNoncopyableConstraintMessage
            )
        )
        return .visitChildren
    }
}
