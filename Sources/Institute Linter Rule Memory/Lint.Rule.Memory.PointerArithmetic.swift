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

/// Raw pointer arithmetic via `unsafe …advanced(by:)` is mechanism the
/// Span family now subsumes for element storage. After the 2026-06
/// de-pointer arc removed raw pointers from memory / storage / buffer / ADT
/// types (a raw `Unsafe*Pointer` is the last resort per `[MEM-SAFE-015]`),
/// this rule is a *prevention* rule: it flags a NEW `unsafe` pointer
/// `.advanced(by:)` so the author reaches for `.span` / `.mutableSpan` /
/// `.withOutputSpan(addingCapacity:)` first per `[MEM-SPAN-003]`.
///
/// Matching discipline:
/// - **Fires only on `unsafe`-marked `.advanced(by:)`.** Under
///   `.strictMemorySafety()` a raw-pointer `.advanced(by:)` is an unsafe
///   operation that carries the `unsafe` keyword; `Strideable.advanced(by:)`
///   (range / index iteration over a `Bound: Strideable`) is a *safe* stdlib
///   operation and carries no `unsafe` — so the rule no longer
///   false-positives on range / index iteration. This is the load-bearing
///   discriminator: an AST-only linter cannot see the receiver's type, but
///   the `unsafe` acknowledgement is the syntactic proxy for "this is a raw
///   pointer."
/// - **Skips `Tests/` / `Experiments/` / `Examples/` paths** — test
///   harnesses legitimately exercise pointer arithmetic against the typed
///   SLI overloads. Mirrors `Lint.Rule.Structure.SingleTypePerFile`.
/// - **Exempts a documented last-resort site** — an adjacent `// SAFETY:`
///   or `// WHY:` justification on the enclosing statement clears the
///   warning (mirrors `[MEM-SAFE-025a]`). The justification both silences
///   the deliberately-retained pointer and documents *why* `[MEM-SAFE-015]`
///   applies there.
///
/// Brand-boundary firings — the typed pointer-arithmetic overloads in a
/// package's `* Standard Library Integration` target (`UnsafePointer + Offset`,
/// the designated home for pointer arithmetic per `[IMPL-010]` / `[INFRA-004]`)
/// — are handled by the consuming package's `.excluding(rules:)` per
/// `[LINT-EXCLUDE-003]`, not here: the rule corpus is brand-form-agnostic by
/// design (`[API-BRAND-001]`).
///
/// Citation: `[MEM-SPAN-003]` (memory-safety skill, the Span note — Span family
/// selection); composes with `[MEM-SAFE-012]`, `[MEM-SAFE-015]`,
/// `[MEM-SAFE-025a]`, `[IMPL-011]`.
extension Lint.Rule {
  public static let `pointer advanced by` = Lint.Rule(
    id: "pointer advanced by",
    default: .warning,
    controls: [
      .init(
        id: "pointer advanced by unsafe",
        source: "func advance(_ pointer: UnsafePointer<Int>, by offset: Int) { _ = unsafe pointer.advanced(by: offset) }",
        path: "Sources/Memory Core/UnsafePointerAdvance.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "pointer advanced by strideable",
        source: "func advance(_ value: Int) { _ = value.advanced(by: 1) }",
        path: "Sources/Memory Core/StrideableAdvance.swift",
        expectation: .clean
      ),
      .init(
        id: "pointer advanced by test fixture",
        source: "func advance(_ pointer: UnsafePointer<Int>, by offset: Int) { _ = unsafe pointer.advanced(by: offset) }",
        path: "Tests/Memory Tests/UnsafePointerAdvance.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // §A brand-owner recognizer: the brand owner's own `* Standard Library
      // Integration` pointer-arithmetic overloads are legitimate-by-
      // construction. Retires the per-package `.excluding(rules:)` stopgap
      // ([LINT-EXCLUDE-003]) referenced in this rule's header.
      if Lint.Brand.owned(Lint.Brand.vocabulary, in: source) { return [] }
      // Scope-exclusion: test / experiment / example trees legitimately
      // exercise raw pointer arithmetic against the SLI overloads.
      // Mirrors `Lint.Rule.Structure.SingleTypePerFile`.
      let path = source.file.filePath
      for excluded in ["Tests", "Experiments", "Examples"] {
        if path == excluded
          || path.hasPrefix("\(excluded)/")
          || path.contains("/\(excluded)/")
        {
          return []
        }
      }
      let visitor = MemoryPointerArithmeticVisitor(
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
internal let memoryPointerArithmeticMessage: Swift.String =
  "[pointer advanced by] [MEM-SPAN-003]: raw pointer arithmetic via "
  + "`unsafe …advanced(by:)` is mechanism. Prefer the Span family: `.span` "
  + "(read the initialised region), `.mutableSpan` (mutate it in place), or "
  + "`.withOutputSpan(addingCapacity:)` (append into the uninitialised tail) "
  + "per [MEM-SPAN-003]/[MEM-SAFE-012]. A raw `Unsafe*Pointer` is the last "
  + "resort per [MEM-SAFE-015]: when one is genuinely required (C / FFI, or "
  + "move-out semantics `MutableSpan` cannot express), keep it `unsafe` and "
  + "add an adjacent `// SAFETY:` or `// WHY:` justification on the enclosing "
  + "statement — that documents the last-resort site and clears this warning. "
  + "(`Strideable.advanced(by:)` for range / index iteration is not pointer "
  + "arithmetic and is not flagged.)"

internal final class MemoryPointerArithmeticVisitor: SyntaxVisitor {
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

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
      return .visitChildren
    }
    guard member.declName.baseName.text == "advanced" else {
      return .visitChildren
    }
    // Single argument labeled `by:`.
    guard node.arguments.count == 1,
      let argument = node.arguments.first,
      argument.label?.text == "by"
    else {
      return .visitChildren
    }
    // Unsafe-discrimination: a raw-pointer `.advanced(by:)` is an unsafe
    // operation under `.strictMemorySafety()` and is wrapped in an
    // `unsafe` expression; `Strideable.advanced(by:)` is a safe stdlib
    // operation and is not. Firing only on the unsafe form eliminates
    // the Strideable (range / index iteration) false-positive class.
    guard isWithinUnsafeExpression(Syntax(node)) else {
      return .visitChildren
    }
    // Last-resort exemption ([MEM-SAFE-015], mirrors [MEM-SAFE-025a]):
    // a documented last-resort site (adjacent `// SAFETY:` / `// WHY:`
    // on the enclosing statement) is the deliberately-retained pointer.
    if hasAdjacentLastResortJustification(Syntax(node)) {
      return .visitChildren
    }
    let location = converter.location(
      for: member.declName.baseName.positionAfterSkippingLeadingTrivia
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
        identifier: "pointer advanced by",
        message: memoryPointerArithmeticMessage
      )
    )
    return .visitChildren
  }

  /// `true` if `node` is within an `unsafe` expression — an
  /// `UnsafeExprSyntax` is an ancestor within the same statement. `unsafe`
  /// is an expression modifier ([MEM-SAFE-002], [IMPL-034]) that wraps its
  /// expression from the left, so the matched call is a descendant of the
  /// `UnsafeExprSyntax` exactly when it was acknowledged unsafe. The walk
  /// stops at the statement / member boundary — `unsafe` cannot span it.
  private func isWithinUnsafeExpression(_ node: Syntax) -> Bool {
    var current: Syntax? = node.parent
    while let candidate = current {
      if candidate.is(UnsafeExprSyntax.self) { return true }
      if candidate.is(CodeBlockItemSyntax.self)
        || candidate.is(MemberBlockItemSyntax.self)
      {
        return false
      }
      current = candidate.parent
    }
    return false
  }

  /// `true` if the enclosing statement (or member item) carries an adjacent
  /// `// SAFETY:` or `// WHY:` justification comment — the institute
  /// convention for documenting an acknowledged last-resort unsafe site
  /// ([MEM-SAFE-025a]).
  private func hasAdjacentLastResortJustification(_ node: Syntax) -> Bool {
    var current: Syntax? = node
    while let candidate = current {
      if let item = candidate.as(CodeBlockItemSyntax.self) {
        return hasAdjacentJustificationComment(item.leadingTrivia)
      }
      if let member = candidate.as(MemberBlockItemSyntax.self) {
        return hasAdjacentJustificationComment(member.leadingTrivia)
      }
      current = candidate.parent
    }
    return false
  }

  /// Walks the leading trivia backwards from the declaration token; returns
  /// `true` if the first contiguous comment block carries a `// SAFETY:` or
  /// `// WHY:` prefix on any line, with no intervening blank line breaking
  /// adjacency. See `memoryTriviaHasAdjacentComment(_:matching:)` in
  /// Shared.swift for the walk's semantics.
  private func hasAdjacentJustificationComment(_ trivia: Trivia) -> Bool {
    memoryTriviaHasAdjacentComment(trivia) { body in
      body.hasPrefix("SAFETY:") || body.hasPrefix("WHY:")
    }
  }
}
