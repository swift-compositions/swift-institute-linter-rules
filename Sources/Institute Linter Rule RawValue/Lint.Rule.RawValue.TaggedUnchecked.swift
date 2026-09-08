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

/// `Tagged<…>(_unchecked: …)` construction sites SHOULD go through a
/// typed alternative when one fits. Citation: `[CONV-015]` (conversions
/// skill — retag/map first, typed arithmetic second, unchecked last
/// resort).
///
/// `_unchecked` bypasses the typed-init alternatives that
/// `swift-tagged`'s standard-library-integration target ships
/// (`ExpressibleBy*Literal`, `LosslessStringConvertible`, …); when one of
/// those typed inits fits, the typed form is preferred because the
/// underlying value is then validated by the literal-protocol's
/// lower-bound contract rather than trusted unchecked.
///
/// AST shape: a `FunctionCallExprSyntax` whose callee identifier resolves
/// to `Tagged` (bare, generic-specialized, or member-accessed) and whose
/// arguments include one labeled `_unchecked`.
///
/// Structural exemptions (contexts where no typed init can apply):
///   - enclosing function named `map` / `retag` — preserve-shape
///     transforms; the closure output is opaque-by-construction or
///     validated upstream by the Tagged construction invariant;
///   - enclosing function attributed `@Test` — tests legitimately
///     exercise the full API surface including `_unchecked` (`~Copyable`
///     Underlying, literal-vs-canonical comparisons, hot-path
///     construction benchmarks).
///
/// Promoted 2026-07-07 from swift-tagged' nested `Lint/` PoC
/// (`Lint.Rule.TaggedDomainAudit`, architecture cohort Phase A) per
/// principal ruling; the PoC's `Tagged` domain-anchor import
/// was a nested-package-mechanism proof and is intentionally dropped —
/// the predicate is purely syntactic.
extension Lint.Rule {
    /// Flags `Tagged<…>(_unchecked:)` construction sites that should use a typed alternative.
    public static let `tagged unchecked with typed alternative` = Lint.Rule(
        id: "tagged unchecked with typed alternative",
        default: .warning,
        controls: [
            .init(
                id: "tagged unchecked with typed alternative unchecked construction",
                source: "let value = Tagged<Tag, Int>(_unchecked: 42)",
                path: "Sources/Raw Value Core/UncheckedConstruction.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "tagged unchecked with typed alternative literal construction",
                source: "let value: Tagged<Tag, Int> = 42",
                path: "Sources/Raw Value Core/LiteralConstruction.swift",
                expectation: .clean
            ),
            .init(
                id: "tagged unchecked with typed alternative test boundary",
                source: "@Test func construction() { _ = Tagged<Tag, Int>(_unchecked: 42) }",
                path: "Tests/Raw Value Tests/UncheckedConstruction.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = RawValueTaggedUncheckedVisitor(
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
internal let rawValueTaggedUncheckedMessage: Swift.String =
    "[tagged unchecked with typed alternative] [CONV-015]: "
    + "`Tagged<…>(_unchecked: …)` bypasses tagged' typed-init alternatives "
    + "(ExpressibleBy*Literal conformances in the Standard Library Integration target). "
    + "Prefer a literal-typed init when the underlying type's literal protocol fits; "
    + "reach for `_unchecked` only when the underlying value is already validated upstream "
    + "and a typed init is genuinely unavailable."

/// Functions whose `_unchecked:` use is structurally authorized — the
/// underlying value is either opaque-by-construction (transform-closure
/// output) or validated by an upstream Tagged construction invariant
/// (phantom-tag swap).
///
/// Inside these contexts, the rule's "prefer a typed
/// init" advice cannot apply because no typed init exists for the
/// opaque or already-validated value.
///
/// Detection: walk up from the call site to the enclosing function
/// decl; if its name matches an entry, exempt the use.
@usableFromInline
internal let rawValueTaggedUncheckedExemptOperations: [Swift.String: Swift.String] = [
    "map": "preserve-shape transform; closure output is opaque-by-construction",
    "retag": "phantom-tag swap; underlying validated upstream by Tagged construction invariant",
]

/// Attribute names whose presence on the enclosing function decl exempts
/// the `_unchecked:` use.
///
/// Currently `@Test` (swift-testing): a test
/// function legitimately exercises the full API surface including
/// `_unchecked` — for example, when Underlying is `~Copyable` (literal
/// init structurally cannot fit), when the test directly compares
/// literal-init against the canonical `_unchecked` form, or when
/// performance hot-path tests measure the barest construction.
///
/// Detection: walk up from the call site to the enclosing function
/// decl; check the decl's attribute list for one of these names.
///
/// Same intuition as `[RULE-EXEMPT-4]` (extension-pattern attribute):
/// the attribute marks the function as belonging to a domain where the
/// rule's recommendation does not apply.
@usableFromInline
internal let rawValueTaggedUncheckedExemptAttributes: [Swift.String: Swift.String] = [
    "Test": "swift-testing test function; tests exercise the full API surface including _unchecked"
]

internal final class RawValueTaggedUncheckedVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    init(
        source: Source.File,
        severity: Diagnostic.Severity,
        converter: SourceLocationConverter
    ) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard Self.calleeIsTagged(node.calledExpression) else {
            return .visitChildren
        }
        // Exempt enclosing-function contexts (function-name or attribute):
        // - preserve-shape transforms (`map`, `retag`) per
        //   `rawValueTaggedUncheckedExemptOperations` — opaque-by-construction
        //   or validated-upstream cases
        // - `@Test`-attributed test functions per
        //   `rawValueTaggedUncheckedExemptAttributes` — tests exercise the
        //   full API surface including `_unchecked`
        if Self.isInsideExemptOperation(Syntax(node)) {
            return .visitChildren
        }
        for argument in node.arguments {
            guard
                let label = argument.label,
                label.tokenKind == .identifier("_unchecked")
            else { continue }
            let location = converter.location(
                for: argument.positionAfterSkippingLeadingTrivia
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
                    identifier: "tagged unchecked with typed alternative",
                    message: rawValueTaggedUncheckedMessage
                )
            )
            break  // one finding per call site
        }
        return .visitChildren
    }

    private static func isInsideExemptOperation(_ node: Syntax) -> Swift.Bool {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let fn = candidate.as(FunctionDeclSyntax.self) {
                if rawValueTaggedUncheckedExemptOperations[fn.name.text] != nil {
                    return true
                }
                if Self.hasExemptAttribute(fn.attributes) {
                    return true
                }
                return false
            }
            current = candidate.parent
        }
        return false
    }

    private static func hasExemptAttribute(_ attributes: AttributeListSyntax) -> Swift.Bool {
        for element in attributes {
            guard case .attribute(let attribute) = element else { continue }
            let name: Swift.String
            if let ident = attribute.attributeName.as(IdentifierTypeSyntax.self) {
                name = ident.name.text
            } else if let member = attribute.attributeName.as(MemberTypeSyntax.self) {
                name = member.name.text
            } else {
                continue
            }
            if rawValueTaggedUncheckedExemptAttributes[name] != nil {
                return true
            }
        }
        return false
    }

    /// Domain-narrowing: the rule fires only when the call's callee
    /// identifier is `Tagged` (bare, generic-specialized, or
    /// member-accessed).
    ///
    /// Non-Tagged `_unchecked:` call sites are out
    /// of scope.
    private static func calleeIsTagged(_ expression: ExprSyntax) -> Bool {
        if let decl = expression.as(DeclReferenceExprSyntax.self) {
            return decl.baseName.text == "Tagged"
        }
        if let generic = expression.as(GenericSpecializationExprSyntax.self) {
            return calleeIsTagged(generic.expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            if member.declName.baseName.text == "Tagged" {
                return true
            }
            // `Tagged.init(_unchecked:)` and `Tagged<Tag, Int>.init(_unchecked:)`
            // parse with `declName == "init"` and `Tagged` as the *base* —
            // recurse through the explicit `.init` spelling the same way
            // `Cardinal.Constructor`'s `calleeTypeName` does.
            if member.declName.baseName.text == "init", let base = member.base {
                return calleeIsTagged(base)
            }
        }
        return false
    }
}
