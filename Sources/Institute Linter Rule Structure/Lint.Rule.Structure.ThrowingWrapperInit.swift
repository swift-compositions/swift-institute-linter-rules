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

/// Wave 4 (mechanization-program) — throwing wrapper `init` whose body
/// is `try base.init(...)` and nothing else MUST also validate the
/// wrapper's stricter invariant.
///
/// Citation: `[PATTERN-020]` (implementation skill, the patterns note —
/// throwing init on wrapper MUST NOT validate only base invariant).
extension Lint.Rule {
    public static let `throwing wrapper init` = Lint.Rule(
        id: "throwing wrapper init",
        default: .warning,
        controls: [
            .init(
                id: "throwing wrapper init base forward",
                source: "struct Wrapper { init(_ raw: Int) throws { self.base = try Base(raw) } }",
                path: "Sources/Structure Core/Wrapper.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "throwing wrapper init validates invariant",
                source: "struct Wrapper { init(_ raw: Int) throws { "
                    + "self.base = try Base(raw); try validate(base) } }",
                path: "Sources/Structure Core/Wrapper.swift",
                expectation: .clean
            ),
            .init(
                id: "throwing wrapper init lax primitive",
                source: "extension Int { init(_ value: Wrapper) throws { "
                    + "self = try UInt(value) } }",
                path: "Sources/Structure Core/Int.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = StructureThrowingWrapperInitVisitor(
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
internal let structureThrowingWrapperInitMessage: Swift.String =
    "[throwing wrapper init] [PATTERN-020]: throwing init body "
    + "is a single `try base.init(...)` forward with no additional validation. "
    + "If the wrapper specializes to a stricter invariant than its base, the "
    + "wrapper's invariant is silently violable. Add the wrapper's validation "
    + "after the base-init call, or rewrite the init to validate the wrapper "
    + "invariant directly."

/// Stdlib primitive types whose extensions are NOT institute wrappers
/// adding stricter invariants — the rule's "wrapper specializes
/// stricter invariant than its base" premise is structurally inverted
/// when the init's enclosing type is one of these.
///
/// An `extension Int` init that accepts an institute Tagged type as a
/// parameter and forwards via `try Int(stripped)` is the LAX type
/// being constructed from a STRICTER source — the body's validation
/// (overflow / range check) is exactly what's needed; there is no
/// "wrapper invariant" to additionally enforce. Firing the rule here
/// inverts the premise.
///
/// Curated allowlist; adding entries requires verifying the type has
/// no additional invariants beyond the body of the throwing init.
@usableFromInline
internal let structureThrowingWrapperInitLaxTypeAllowlist: Swift.Set<Swift.String> = [
    "Int", "Int8", "Int16", "Int32", "Int64",
    "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Float", "Float16", "Float32", "Float64", "Float80", "Double",
    "Bool",
    "String", "Substring", "Character",
]

internal final class StructureThrowingWrapperInitVisitor: SyntaxVisitor {
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

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.signature.effectSpecifiers?.throwsClause != nil else {
            return .visitChildren
        }
        guard let body = node.body else { return .visitChildren }
        let statements = body.statements
        guard statements.count == 1 else { return .visitChildren }
        guard let only = statements.first?.item else { return .visitChildren }
        // The predicate targets specifically a *forward to the base
        // type's own initializer* (`try base.init(...)` / bare
        // `try Base(...)`, per the doc and message) — not merely "any
        // single `try` statement". A single-`try` body calling something
        // else (`try someOtherOperation()`, `try validate(x)`, an
        // `init(from:) throws` that forwards through a non-constructor
        // decoder API) is not the base-init-forward shape the doc and
        // message describe, and is not itself evidence that the
        // wrapper's stricter invariant goes unvalidated.
        guard isBaseInitializerTryForward(Syntax(only)) else { return .visitChildren }
        // Skip when the init's enclosing type is a stdlib lax primitive
        // (Int, UInt, Float, etc.). The rule's "wrapper specializes
        // stricter invariant than its base" premise inverts when the
        // enclosing type IS the lax type and the parameter is the
        // stricter institute type — the body's validation (overflow /
        // range check from `try Int(stripped)`) is exactly what's
        // needed; there is no wrapper invariant to additionally enforce.
        if isInsideExtensionOnLaxType(Syntax(node)) {
            return .visitChildren
        }
        let location = converter.location(
            for: node.initKeyword.positionAfterSkippingLeadingTrivia
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
                identifier: "throwing wrapper init",
                message: structureThrowingWrapperInitMessage
            )
        )
        return .visitChildren
    }

    private func isInsideExtensionOnLaxType(_ node: Syntax) -> Swift.Bool {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let ext = candidate.as(ExtensionDeclSyntax.self) {
                if let identifier = ext.extendedType.as(IdentifierTypeSyntax.self) {
                    return structureThrowingWrapperInitLaxTypeAllowlist.contains(
                        identifier.name.text
                    )
                }
                if let member = ext.extendedType.as(MemberTypeSyntax.self) {
                    return structureThrowingWrapperInitLaxTypeAllowlist.contains(member.name.text)
                }
                return false
            }
            // Once we cross a type-decl boundary that ISN'T an extension
            // (struct / class / enum / actor / protocol), the rule's
            // wrapper premise applies and the allowlist doesn't cover.
            if candidate.is(StructDeclSyntax.self)
                || candidate.is(ClassDeclSyntax.self)
                || candidate.is(EnumDeclSyntax.self)
                || candidate.is(ActorDeclSyntax.self)
                || candidate.is(ProtocolDeclSyntax.self)
            {
                return false
            }
            current = candidate.parent
        }
        return false
    }

    /// Extracts the `TryExprSyntax` from a single-statement body's item,
    /// whether it's the item directly, wrapped as an `ExprSyntax`, a
    /// `let`/`var` binding's initializer (`let base = try Base(raw)`),
    /// or (pre-operator-folding) one element of an unfolded
    /// `SequenceExprSyntax`. The variable-declaration case closes the
    /// asymmetry where `self.x = try Base(...)` fired but the equally
    /// unvalidated `let base = try Base(raw)` did not.
    private func extractTryExpr(_ syntax: Syntax) -> TryExprSyntax? {
        // #28 nit 1: casting `Syntax` → `ExprSyntax` → `TryExprSyntax` is
        // unreachable once `Syntax` → `TryExprSyntax` (above) has already been
        // tried — `as(_:)` does not change the underlying node kind, so the
        // second cast can only re-match what the first already caught. Unlike
        // the pack's genuinely defensive dual-shape branches (which guard a
        // folded-vs-unfolded difference that CAN occur), this guards nothing.
        if let tryExpr = syntax.as(TryExprSyntax.self) {
            return tryExpr
        }
        if let variableDecl = syntax.as(VariableDeclSyntax.self),
            variableDecl.bindings.count == 1,
            let binding = variableDecl.bindings.first,
            let initializer = binding.initializer,
            let tryExpr = initializer.value.as(TryExprSyntax.self)
        {
            return tryExpr
        }
        if let sequence = syntax.as(SequenceExprSyntax.self) {
            for element in sequence.elements {
                if let tryExpr = element.as(TryExprSyntax.self) {
                    return tryExpr
                }
            }
        }
        return nil
    }

    /// True if `syntax` is a top-level `try` statement whose (possibly
    /// assignment-wrapped) expression is a call to the base type's own
    /// initializer — `try self.init(...)`, `try Type.init(...)`, bare
    /// `try Type(...)`, or one of those forms on the right-hand side of
    /// an assignment (`try self.base = Base(raw)` / `self.base = try
    /// Base(raw)`). A `try` expression calling anything else (a method,
    /// a free function, a decoder API) is not the base-init-forward
    /// shape the doc and message describe.
    private func isBaseInitializerTryForward(_ syntax: Syntax) -> Swift.Bool {
        // Raw (pre-operator-folding) assignment sequence: exactly three
        // elements with `=` in the middle. SwiftParser's raw grammar
        // attaches a prefix `try` to only the immediately following
        // primary/postfix expression, so `try` can land on EITHER side
        // depending on where it's written in source: `self.base = try
        // Base(raw)` wraps the RHS constructor call directly; `try
        // self.base = Base(raw)` instead wraps the bare LHS, leaving the
        // RHS unwrapped. Both spellings put the assignment under `try`
        // (Swift accepts either); what this rule cares about — whether
        // the RHS is a constructor call — doesn't depend on which side
        // the keyword landed on, so both are checked directly here
        // rather than through `extractTryExpr`, which (grabbing "the
        // first `TryExprSyntax` element") previously returned the bare
        // LHS's narrow `.expression` for the `try LHS = RHS` spelling and
        // lost the RHS entirely.
        if let sequence = syntax.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            if elements.count == 3, elements[1].is(AssignmentExprSyntax.self) {
                let sawTry =
                    elements[0].is(TryExprSyntax.self) || elements[2].is(TryExprSyntax.self)
                guard sawTry else { return false }
                let rhs = elements[2].as(TryExprSyntax.self)?.expression ?? elements[2]
                return isConstructorCall(rhs)
            }
        }
        guard let tryExpr = extractTryExpr(syntax) else { return false }
        let inner = tryExpr.expression
        if let infix = inner.as(InfixOperatorExprSyntax.self),
            infix.operator.is(AssignmentExprSyntax.self)
        {
            return isConstructorCall(infix.rightOperand)
        }
        return isConstructorCall(inner)
    }

    /// True if `expr` (after peeling one layer of parens) is a
    /// `FunctionCallExprSyntax` whose callee resolves to an
    /// initializer: `self.init(...)` / `Type.init(...)`
    /// (`MemberAccessExprSyntax` with `declName == "init"`), or a bare
    /// call to an upper-camel-case identifier (`Type(...)`) — the
    /// house convention for a constructor call, as distinct from a
    /// lowercase method/free-function call.
    private func isConstructorCall(_ expr: ExprSyntax) -> Swift.Bool {
        var current = expr
        if let tuple = current.as(TupleExprSyntax.self),
            tuple.elements.count == 1,
            let only = tuple.elements.first?.expression,
            tuple.elements.first?.label == nil
        {
            current = only
        }
        guard let call = current.as(FunctionCallExprSyntax.self) else { return false }
        return calleeIsConstructor(call.calledExpression)
    }

    private func calleeIsConstructor(_ expr: ExprSyntax) -> Swift.Bool {
        if let generic = expr.as(GenericSpecializationExprSyntax.self) {
            return calleeIsConstructor(generic.expression)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text == "init"
        }
        if let decl = expr.as(DeclReferenceExprSyntax.self) {
            guard let first = decl.baseName.text.first else { return false }
            return first.isUppercase
        }
        return false
    }
}
