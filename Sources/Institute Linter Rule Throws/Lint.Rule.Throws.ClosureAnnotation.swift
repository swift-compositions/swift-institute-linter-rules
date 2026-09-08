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

/// Closures inside a `throws(E)` context MUST carry an explicit
/// `throws(E)` annotation when they contain `try`. Citation: `[API-ERR-004]`.
///
/// Coordination note: a `try` on a stdlib `rethrows` higher-order method
/// inside a `throws(E)` closure can also fire `result wrapper for rethrows
/// shim` ([IMPL-109]) on the same site. The two remedies conflict — this
/// rule's fix is "add `throws(E)` to the closure," the shim's fix is
/// "materialise `Result<T, E>` and stop the `try` from propagating
/// unadapted." Applying only one leaves the other rule's finding
/// unresolved; there is currently no suppression or precedence between
/// them, so a site hitting both must apply the shim first (which removes
/// the bare `try` this rule keys on) and only annotate remaining,
/// non-rethrows `try`s.
extension Lint.Rule {
    public static let `closure typed throws annotation` = Lint.Rule(
        id: "closure typed throws annotation",
        default: .warning,
        controls: [
            .init(
                id: "closure typed throws annotation inferred closure",
                source: "func read<E: Swift.Error>(_ values: [Int]) throws(E) { "
                    + "_ = values.map { try load($0) } }",
                path: "Sources/Throws Consumer/InferredThrowingClosure.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "closure typed throws annotation explicit closure",
                source: "func read<E: Swift.Error>(_ values: [Int]) throws(E) { "
                    + "_ = values.map { (value: Int) throws(E) -> Int in "
                    + "try load(value) } }",
                path: "Sources/Throws Consumer/TypedThrowingClosure.swift",
                expectation: .clean
            ),
            .init(
                id: "closure typed throws annotation expect throws boundary",
                source: "func read() throws(Read.Error) { "
                    + "#expect(throws: Read.Error.self) { try load() } }",
                path: "Sources/Throws Consumer/ExpectThrows.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ThrowsClosureAnnotationVisitor(
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
internal let throwsClosureAnnotationMessage: Swift.String =
    "[closure typed throws annotation] [API-ERR-004]: closure inside a "
    + "`throws(E)` context contains `try` but lacks an explicit "
    + "`throws(E)` annotation — Swift 6.2 infers `any Error` and erases "
    + "the typed throw."

internal func throwsIsTypedThrows(_ clause: ThrowsClauseSyntax?) -> Swift.Bool {
    guard let clause else { return false }
    return clause.type != nil
}

/// Returns true if `node` is the trailing closure of a `#expect(throws:)`
/// macro expansion. The macro's `throws:` argument signature carries the
/// expected error; the closure body's job is to throw — Swift Testing
/// then asserts that the body threw the expected error. The macro's
/// contract takes `any Error` by design, so annotating the closure with
/// `() throws(E) in` is semantically meaningless: the macro already knows
/// which `E` to assert against from its labeled argument.
///
/// Additionally, on Swift 6.3.2 the annotation triggers a SIL crash in
/// `LifetimeDependenceDiagnostics` when the closure body holds
/// `~Copyable` lifetime-dependent types (e.g., `Binary.Cursor`). The
/// carve-out preserves correct typed-throws coverage at the macro
/// boundary without forcing source through a compiler-blocked corner.
///
/// Citation: [API-ERR-004] (rule's primary statement);
/// [RULE-EXEMPT-4]-shaped attribute/macro carve-out.
///
/// Detection: walks one level up to `MacroExpansionExprSyntax`,
/// checks the macro name is `expect`, and verifies the argument list
/// contains a `throws:` labeled argument.
internal func throwsClosureIsInsideExpectThrows(_ node: ClosureExprSyntax) -> Swift.Bool {
    guard let parent = node.parent else { return false }
    guard let macro = parent.as(MacroExpansionExprSyntax.self) else { return false }
    guard macro.macroName.text == "expect" else { return false }
    for argument in macro.arguments {
        if argument.label?.text == "throws" {
            return true
        }
    }
    return false
}

/// Returns true if the node is inside an enclosing `DoStmtSyntax` whose
/// `catchClauses` contain at least one catch body that ends with a
/// `return` of a value (the Result-materialization shape). Stops the
/// walk at any enclosing `ClosureExprSyntax` — the closure boundary.
///
/// A `do` statement materializes a `try` iff (i) it has at least one catch
/// clause, (ii) at least one clause is catch-all, and (iii) every clause
/// neither throws nor propagates (#19 defect 3).
internal func throwsClosureTryIsInsideMaterializingDoCatch(_ node: Syntax) -> Swift.Bool {
    var current: Syntax? = node.parent
    while let candidate = current {
        if let doStmt = candidate.as(DoStmtSyntax.self) {
            if !doStmt.catchClauses.isEmpty,
                doStmt.catchClauses.contains(where: throwsClosureCatchIsCatchAll),
                doStmt.catchClauses.allSatisfy(throwsClosureCatchIsNonPropagating)
            {
                return true
            }
        }
        if candidate.is(ClosureExprSyntax.self) { return false }
        current = candidate.parent
    }
    return false
}

/// True when the catch clause has no typed/`where`-guarded pattern — it
/// catches every error, not a subset. A typed or `where`-guarded catch is
/// not exhaustive: some errors fall through uncaught, so the `do` does not
/// fully materialize the `try`.
internal func throwsClosureCatchIsCatchAll(_ clause: CatchClauseSyntax) -> Swift.Bool {
    clause.catchItems.isEmpty
        || clause.catchItems.allSatisfy { $0.pattern == nil && $0.whereClause == nil }
}

/// Returns true if the catch clause's body materializes the error
/// rather than propagating it. Materialization takes one of two
/// shapes in the [IMPL-109] pattern:
///
/// 1. Return-form: `catch { return .failure(error) }` — the catch
///    returns a Result/Optional/etc. value to the enclosing scope.
/// 2. Side-effect-form: `catch { result = .failure(error) }` — the
///    catch assigns to a captured variable; the outer scope reads
///    the variable after the closure returns.
///
/// Both shapes mean the closure itself doesn't propagate the error.
/// A catch that contains a `ThrowStmt`, or a non-optional `try` (a call
/// that can itself throw, e.g. `try fallback()`), IS propagating and DOES
/// need the closure to be annotated. Detection: a catch is
/// non-propagating iff its body contains NO `ThrowStmt` and NO
/// non-optional `try` at any depth (excluding nested closures, which have
/// their own boundary).
internal func throwsClosureCatchIsNonPropagating(_ clause: CatchClauseSyntax) -> Swift.Bool {
    let finder = ThrowsClosureCatchPropagationFinder(viewMode: .sourceAccurate)
    finder.walk(clause.body)
    return !finder.foundPropagation
}

internal final class ThrowsClosureAnnotationVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    var typedThrowsDepth: Swift.Int = 0

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
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
                identifier: "closure typed throws annotation",
                message: throwsClosureAnnotationMessage
            )
        )
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if throwsIsTypedThrows(node.signature.effectSpecifiers?.throwsClause) {
            typedThrowsDepth += 1
        }
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) {
        if throwsIsTypedThrows(node.signature.effectSpecifiers?.throwsClause) {
            typedThrowsDepth -= 1
        }
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if throwsIsTypedThrows(node.signature.effectSpecifiers?.throwsClause) {
            typedThrowsDepth += 1
        }
        return .visitChildren
    }
    override func visitPost(_ node: InitializerDeclSyntax) {
        if throwsIsTypedThrows(node.signature.effectSpecifiers?.throwsClause) {
            typedThrowsDepth -= 1
        }
    }

    // #19 defect 4, item 1: accessors (and, by extension, subscripts — a
    // subscript's throws clause lives on its accessors, so no
    // `SubscriptDeclSyntax` override is needed or correct).
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        if throwsIsTypedThrows(node.effectSpecifiers?.throwsClause) {
            typedThrowsDepth += 1
        }
        return .visitChildren
    }
    override func visitPost(_ node: AccessorDeclSyntax) {
        if throwsIsTypedThrows(node.effectSpecifiers?.throwsClause) {
            typedThrowsDepth -= 1
        }
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        // #19 defect 4, item 2: a typed-throws closure both COUNTS as a
        // typed-throws context for its own children and STAYS EXEMPT itself
        // (it already carries the annotation it would otherwise be flagged
        // for lacking). `wasInTypedContext` is read BEFORE the increment, or
        // a typed closure at file scope would flag itself.
        let isTyped = throwsIsTypedThrows(node.signature?.effectSpecifiers?.throwsClause)
        let wasInTypedContext = typedThrowsDepth > 0
        if isTyped { typedThrowsDepth += 1 }
        guard wasInTypedContext, !isTyped else { return .visitChildren }
        // Carve-out: `#expect(throws:)` macro expansion. The macro's
        // `throws:` argument carries the expected error; the closure
        // annotation is semantically meaningless. Additionally, the
        // annotation triggers a Swift 6.3.2 SIL crash when the body
        // holds ~Copyable lifetime-dependent types. See
        // `throwsClosureIsInsideExpectThrows` for full rationale and
        // citation.
        if throwsClosureIsInsideExpectThrows(node) {
            return .visitChildren
        }
        let finder = ThrowsClosureTryFinder(viewMode: .sourceAccurate)
        for statement in node.statements {
            finder.walk(statement)
            if finder.found { break }
        }
        guard finder.found else { return .visitChildren }
        let position: AbsolutePosition
        if let signature = node.signature {
            position = signature.positionAfterSkippingLeadingTrivia
        } else {
            position = node.leftBrace.positionAfterSkippingLeadingTrivia
        }
        emit(at: position)
        return .visitChildren
    }
    override func visitPost(_ node: ClosureExprSyntax) {
        if throwsIsTypedThrows(node.signature?.effectSpecifiers?.throwsClause) {
            typedThrowsDepth -= 1
        }
    }
}
