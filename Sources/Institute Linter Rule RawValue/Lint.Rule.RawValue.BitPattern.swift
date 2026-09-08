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

/// R4 — `X(bitPattern: …rawValue)` integration-overload anti-pattern.
///
/// Subsumes the regex `bitpattern_rawvalue_chain_anti_pattern`. The AST
/// predicate is a `FunctionCallExprSyntax` carrying a `bitPattern:`
/// labeled argument whose expression chains through a `.rawValue`
/// member access (anywhere inside the argument expression).
///
/// Typename-swap evasion (`Int(bitPattern:)` vs `UInt(bitPattern:)` vs
/// `self.init(bitPattern:)` vs `Int.init(bitPattern:)` vs
/// `Int8(bitPattern:)` …) is closed natively: every form parses to a
/// `FunctionCallExprSyntax` carrying the same labeled argument. The
/// predicate doesn't constrain the callee, so all spellings hit.
///
/// References:
/// - the cardinal/ordinal/vector enforcement design note
///   §"R4. `Int(bitPattern: <something>.rawValue ...)`"
/// - the SwiftSyntax-based custom-linter investigation note
///   §"Q2 — Evasion-class closure matrix" (typename-swap row)
extension Lint.Rule {
  /// Flags `init(bitPattern:)` calls whose argument chains through `.rawValue`, bypassing the typed conversion hierarchy ([CONV-016]).
  public static let `bitpattern rawvalue chain` = Lint.Rule(
    id: "bitpattern rawvalue chain",
    default: .warning,
    controls: [
      .init(
        id: "bitpattern rawvalue chain labeled raw value",
        source: "let value = Int(bitPattern: index.rawValue)",
        path: "Sources/Raw Value Core/BitPatternRawValue.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "bitpattern rawvalue chain typed argument",
        source: "let value = Int(bitPattern: index)",
        path: "Sources/Raw Value Core/BitPatternTyped.swift",
        expectation: .clean
      ),
      .init(
        id: "bitpattern rawvalue chain different label",
        source: "let value = Int(other: index.rawValue)",
        path: "Sources/Raw Value Core/OtherInitializer.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // §A brand-owner recognizer: the owner's own `Int(bitPattern:
      // brand.rawValue)` integration overload ([INFRA-002]) is
      // legitimate-by-construction. Retires the per-package
      // `.excluding(rules:)` stopgap ([LINT-EXCLUDE-*]).
      if Lint.Brand.owned(Lint.Brand.vocabulary, in: source) { return [] }
      let visitor = RawValueBitPatternVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

private let bitpatternRawvalueChainMessage: Swift.String =
  "[bitpattern rawvalue chain] [CONV-016]: `init(bitPattern:)` whose argument chains "
  + "through `.rawValue` — including `Int(...)`, `UInt(...)`, `Int.init(...)`, "
  + "`self.init(...)`, and other syntactic equivalents — bypasses the canonical "
  + "preference hierarchy. Prefer `.retag()` / `.map()` (Tier 1/2) before resorting "
  + "to the [INFRA-002] integration overload — and when you do use the overload, "
  + "pass the typed value directly: `Int(bitPattern: foo)` not "
  + "`Int(bitPattern: foo.rawValue)`. If this site IS the [INFRA-002] integration "
  + "overload definition itself, escalate to supervisor and apply "
  + "`// swift-linter:disable:next bitpattern rawvalue chain  // reason: <citation>`."

internal final class RawValueBitPatternVisitor: SyntaxVisitor {
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
    for arg in node.arguments {
      guard let label = arg.label, label.text == "bitPattern" else { continue }
      guard Self.containsRawValueAccess(arg.expression) else { continue }
      let location = converter.location(for: label.positionAfterSkippingLeadingTrivia)
      matches.append(
        Diagnostic.Record(
          location: Source.Location(
            fileID: source.fileID,
            filePath: source.filePath,
            line: location.line,
            column: location.column
          ),
          severity: severity,
          identifier: "bitpattern rawvalue chain",
          message: bitpatternRawvalueChainMessage
        )
      )
    }
    return .visitChildren
  }

  private static func containsRawValueAccess(_ expr: ExprSyntax) -> Swift.Bool {
    let finder = RawValueBitPatternFinder(viewMode: .sourceAccurate)
    finder.walk(expr)
    return finder.found
  }
}
