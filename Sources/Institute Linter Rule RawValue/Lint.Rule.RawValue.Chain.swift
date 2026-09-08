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

/// R3 — chained `.rawValue.X` member access.
///
/// Subsumes the regex pair `chained_rawvalue_access_anti_pattern` +
/// `chained_rawvalue_access_paren_evasion`. The AST predicate is a
/// `MemberAccessExprSyntax` whose base, after peeling parenthesized
/// wrappers, is itself a `MemberAccessExprSyntax` whose member name is
/// `rawValue`.
///
/// Paren-wrap evasion `(x.rawValue).foo()` collapses into the same
/// predicate: `TupleExprSyntax` wrapping a single expression is
/// semantically transparent, so peeling it yields the same
/// `MemberAccessExprSyntax(base: x, name: rawValue)` shape.
///
/// References:
/// - the cardinal/ordinal/vector enforcement design note
///   §"R3. `.rawValue.` chains"
/// - the SwiftSyntax-based custom-linter investigation note
///   §"Q2 — Evasion-class closure matrix" (paren-wrap row)
extension Lint.Rule {
  /// Flags chained `.rawValue.member` access, including the paren-wrapped `(x.rawValue).member` form, which escapes the typed system ([CONV-016]).
  public static let `chained rawvalue access` = Lint.Rule(
    id: "chained rawvalue access",
    default: .warning,
    controls: [
      .init(
        id: "chained rawvalue access member chain",
        source: "let normalized = value.rawValue.lowercased()",
        path: "Sources/Raw Value Core/ChainedAccess.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "chained rawvalue access terminal access",
        source: "let raw = value.rawValue",
        path: "Sources/Raw Value Core/TerminalAccess.swift",
        expectation: .clean
      ),
      .init(
        id: "chained rawvalue access string boundary",
        source: #"let example = "value.rawValue.lowercased()""#,
        path: "Tests/Raw Value Tests/ChainExample.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // §A brand-owner recognizer: same-package `.rawValue.<member>`
      // chains on the owner's brand are legitimate-by-construction.
      // Retires the per-package `.excluding(rules:)` stopgap
      // ([LINT-EXCLUDE-*]).
      if Lint.Brand.owned(Lint.Brand.vocabulary, in: source) { return [] }
      let visitor = RawValueChainVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

private let chainedRawvalueAccessMessage: Swift.String =
  "[chained rawvalue access] [CONV-016]: chaining `.rawValue.method()` (or "
  + "paren-wrapped `(x.rawValue).method()`, which is semantically identical) escapes "
  + "the typed system. Prefer `.retag()` (Tier 1) / `.map()` (Tier 2) / `Type.min(a, b)` "
  + "/ a typed accessor exposed by the wrapper, per [INFRA-103]. If the wrapper IS "
  + "what this site implements (typed-system bottom-out), escalate to supervisor and "
  + "apply `// swift-linter:disable:next chained rawvalue access  // reason: <citation>`."

internal final class RawValueChainVisitor: SyntaxVisitor {
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

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    guard let base = node.base else { return .visitChildren }
    let unwrapped = Self.peelParens(base)
    guard let baseAccess = unwrapped.as(MemberAccessExprSyntax.self),
      baseAccess.declName.baseName.text == "rawValue"
    else { return .visitChildren }
    let token = node.declName.baseName
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
        identifier: "chained rawvalue access",
        message: chainedRawvalueAccessMessage
      )
    )
    return .visitChildren
  }

  /// Peels syntactic wrappers that are semantically transparent for this
  /// predicate's purposes: parenthesization (`(x.rawValue)`), optional
  /// chaining (`x.rawValue?`), and force unwrap (`x.rawValue!`). Each is
  /// a one-character evasion that would otherwise reopen the hole the
  /// paren-peel closed.
  private static func peelParens(_ expr: ExprSyntax) -> ExprSyntax {
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
      if let optionalChain = current.as(OptionalChainingExprSyntax.self) {
        current = optionalChain.expression
        continue
      }
      if let forceUnwrap = current.as(ForceUnwrapExprSyntax.self) {
        current = forceUnwrap.expression
        continue
      }
      break
    }
    return current
  }
}
