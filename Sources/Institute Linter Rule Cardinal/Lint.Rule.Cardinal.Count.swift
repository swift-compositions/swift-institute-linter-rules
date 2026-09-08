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
internal import SwiftOperators
internal import SwiftSyntax

/// R1 — `<expr>.count - 1` and its semantically-equivalent rewrites.
///
/// Subsumes the regex pair `cardinal_count_minus_one_anti_pattern` +
/// `cardinal_count_minus_one_evasion`. After operator folding the four
/// surface-text variants collapse to two AST predicates:
///
/// 1. **Subtraction with literal `1`** — an `InfixOperatorExprSyntax`
///    whose operator is `-`, whose right operand is the integer literal
///    `1`, and whose left operand contains a member-access expression
///    of shape `<expr>.count` (`MemberAccessExprSyntax` with
///    `declName.baseName.text == "count"`). Catches member-access
///    `seq.count - 1`, paren-wrapped `(seq.count) - 1`, cast-outside
///    `Double(seq.count) - 1`, and operand-reorder `seq.count - i - 1`
///    (left-associativity makes the outer `- 1` binary-bind to a left
///    subtree that contains `seq.count`).
///
/// 2. **Algebraic-flip via comparison** — an `InfixOperatorExprSyntax`
///    whose operator is one of `<`, `<=`, `==`, `!=`, `>=`, `>`, where
///    one side has the shape `<expr> + 1` (commutative) and the other
///    side contains a member-access expression `<expr>.count`. Catches
///    `i + 1 < seq.count`, `1 + i < seq.count`, `seq.count == i + 1`, etc.
///
/// Bare-identifier `count` in scope (loop variable, local binding
/// `let count = ...`, function parameter named `count`) is intentionally
/// out-of-scope: the [INFRA-200] typed-cardinal rationale concerns
/// Collection-shaped `count`, and member-access form is the access
/// pattern for `Collection.count`. Bare-token analysis cannot
/// distinguish a Collection.count escape from an in-scope local that
/// happens to share the name.
///
/// Operand-reorder `(seq.count - i - 1)` — uncatchable by regex — is
/// caught by predicate 1: left-associativity parses the subexpression
/// as `((seq.count - i) - 1)`, whose outer `-` has RHS `1` and LHS
/// `seq.count - i` (which contains the member-access `seq.count`).
///
/// Comments-as-code is a non-issue at the AST level: comments are
/// `Trivia`, not part of the expression grammar; the visitor never
/// reaches them.
///
/// References:
/// - the cardinal/ordinal/vector enforcement design note
///   §"R1. `count - 1` and family"
/// - the SwiftSyntax-based custom-linter investigation note
///   §"Q3 — Deferred AST-rule unblocking matrix"
extension Lint.Rule {
    /// Flags `<expr>.count - 1` and its semantic equivalents (paren-wrap, cast-outside, algebraic-flip, operand-reorder), which indicate an untyped `count: Int` ([INFRA-200]).
    public static let `count minus one` = Lint.Rule(
        id: "count minus one",
        default: .warning,
        controls: [
            .init(
                id: "count minus one member access",
                source: "let last = values.count - 1",
                path: "Sources/Cardinal Consumer/MemberCount.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "count minus one different literal",
                source: "let remaining = values.count - 2",
                path: "Sources/Cardinal Consumer/CountMinusTwo.swift",
                expectation: .clean
            ),
            .init(
                id: "count minus one bare binding",
                source: "let count = limit\nlet last = count - 1",
                path: "Sources/Cardinal Consumer/BareCount.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let folded = OperatorTable.standardOperators.foldAll(
                source.tree,
                errorHandler: { _ in }
            )
            let visitor = CardinalCountVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(folded)
            return visitor.matches
        }
    )
}

@usableFromInline
internal let cardinalCountMinusOneMessage: Swift.String =
    "[count minus one] [INFRA-200]: `<expr>.count - 1` (or syntactic "
    + "equivalents — paren-wrap `(seq.count) - 1`, cast-outside `Double(seq.count) - 1`, "
    + "algebraic-flip `+ 1 [<=] seq.count`, operand-reorder `seq.count - i - 1`) "
    + "indicates `count: Int` not `count: Cardinal` (the typed form would not compile). "
    + "Use `.subtract.saturating(.one)` / `.subtract.exact(.one)` / typed `count - .one` "
    + "per [INFRA-025], or for stdlib-Int sites where no typed surface is available "
    + "either (α) use the stdlib's named idiom for the concept (`indices.dropLast()`, "
    + "`.last`, `endIndex - 1`) or (β) escalate to supervisor and apply "
    + "`// swift-linter:disable:next count minus one` with a "
    + "`// REASON: <citation>` continuation."

internal final class CardinalCountVisitor: SyntaxVisitor {
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

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        guard let binOp = node.operator.as(BinaryOperatorExprSyntax.self) else {
            return .visitChildren
        }
        let opText = binOp.operator.text

        if opText == "-",
            Self.isLiteralOne(node.rightOperand),
            Self.isCountDerivedExpression(node.leftOperand)
        {
            report(at: binOp.operator)
            return .visitChildren
        }

        if Self.isComparisonOperator(opText) {
            if Self.isIndexPlusOne(node.leftOperand),
                Self.isCountDerivedExpression(node.rightOperand)
            {
                report(at: binOp.operator)
            } else if Self.isIndexPlusOne(node.rightOperand),
                Self.isCountDerivedExpression(node.leftOperand)
            {
                report(at: binOp.operator)
            }
        }

        return .visitChildren
    }

    func report(at token: TokenSyntax) {
        let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "count minus one",
                message: cardinalCountMinusOneMessage
            )
        )
    }

    static func isLiteralOne(_ expr: ExprSyntax) -> Bool {
        guard let lit = expr.as(IntegerLiteralExprSyntax.self) else { return false }
        return lit.literal.text == "1"
    }

    static func isComparisonOperator(_ text: Swift.String) -> Bool {
        switch text {
        case "<", "<=", "==", "!=", ">=", ">": return true
        default: return false
        }
    }

    static func isPlusOne(_ expr: ExprSyntax) -> Bool {
        guard let infix = expr.as(InfixOperatorExprSyntax.self),
            let binOp = infix.operator.as(BinaryOperatorExprSyntax.self),
            binOp.operator.text == "+"
        else { return false }
        return isLiteralOne(infix.leftOperand) || isLiteralOne(infix.rightOperand)
    }

    /// The algebraic-flip arm's `<index> + 1` operand: a `+ 1` shape whose
    /// OTHER (non-literal) operand is not itself count-derived.
    ///
    /// Predicate 2 exists to catch an INDEX compared against a count
    /// (`i + 1 < seq.count` is `i < seq.count - 1` rewritten). When both
    /// sides are cardinalities — `a.count == b.count + 1` — nothing is
    /// being indexed: that is a comparison of two counts, the canonical
    /// shape of a test assertion about collection size, and it compiles
    /// unchanged under a typed `Cardinal` (`Cardinal` supports `+ .one`
    /// and `==`). [INFRA-200]'s "the typed form would not compile" test
    /// therefore does not hold, so the finding was a false positive.
    ///
    /// Confirmed instance: swift-institute/.github#90 comment 5150641576
    /// item 1(b) — `#expect(secure.middleware.count == plain.middleware.count + 1)`,
    /// 2 findings in one package.
    ///
    /// Real index arithmetic is unaffected: `array[count - 1]` and every
    /// other predicate-1 subtraction shape never reaches this function, and
    /// `i + 1 < seq.count` still fires because `i` is not count-derived.
    static func isIndexPlusOne(_ expr: ExprSyntax) -> Bool {
        guard let infix = expr.as(InfixOperatorExprSyntax.self),
            let binOp = infix.operator.as(BinaryOperatorExprSyntax.self),
            binOp.operator.text == "+"
        else { return false }
        if isLiteralOne(infix.rightOperand) {
            return !isCountDerivedExpression(infix.leftOperand)
        }
        if isLiteralOne(infix.leftOperand) {
            return !isCountDerivedExpression(infix.rightOperand)
        }
        return false
    }

    /// Returns true when `expr`, after peeling the specific wrapper
    /// shapes the doc's evasion matrix names (parens, and a single-
    /// unlabeled-argument cast call like `Double(...)`), IS itself a
    /// `.count` member access, or a `-` subtraction chain whose
    /// (recursively unwrapped) left operand resolves the same way.
    ///
    /// This intentionally does NOT search arbitrarily deep into an
    /// unrelated subtree: `grid[rows.count].height - 1` must not fire
    /// merely because `.count` appears somewhere inside the left
    /// operand — the `- 1` here applies to `.height`, not `.count`. The
    /// doc's own operand-reorder example, `seq.count - i - 1`, parses as
    /// `(seq.count - i) - 1`; recursing one `-` level into the left
    /// operand (and no further) is exactly the shape that example
    /// requires, without over-matching subscript/property chains that
    /// merely contain a `.count` somewhere.
    static func isCountDerivedExpression(_ expr: ExprSyntax) -> Bool {
        let unwrapped = peelCountWrappers(expr)
        if let member = unwrapped.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "count"
        {
            return true
        }
        if let infix = unwrapped.as(InfixOperatorExprSyntax.self),
            let binOp = infix.operator.as(BinaryOperatorExprSyntax.self),
            binOp.operator.text == "-"
        {
            return isCountDerivedExpression(infix.leftOperand)
        }
        return false
    }

    /// Peels parenthesization and a single-unlabeled-argument call
    /// (the cast-outside shape, `Double(seq.count)`) — the two wrapper
    /// forms the doc's evasion matrix names as semantically transparent
    /// for this predicate.
    static func peelCountWrappers(_ expr: ExprSyntax) -> ExprSyntax {
        var current = expr
        while true {
            if let tuple = current.as(TupleExprSyntax.self),
                tuple.elements.count == 1,
                let only = tuple.elements.first?.expression,
                tuple.elements.first?.label == nil
            {
                current = only
                continue
            }
            if let call = current.as(FunctionCallExprSyntax.self),
                call.arguments.count == 1,
                let onlyArg = call.arguments.first,
                onlyArg.label == nil,
                call.trailingClosure == nil
            {
                current = onlyArg.expression
                continue
            }
            break
        }
        return current
    }
}
