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

internal import Byte
public import Lint
internal import SwiftSyntax

/// Diagnostic-emitting rules' message strings MUST follow the educational-
/// diagnostic format `[<rule_id>] <citation>: <description>`.
/// Citation: `[API-NAME-009]`.
///
/// Mirrors `validate-diagnostic-format.py` (swift-institute/.github, Wave 4
/// mechanization 2026-05-11). Mechanical narrow check, verbatim from the
/// Python: a `static let message` declaration whose initializer is a string
/// literal (or a `+`-chain of string literals) in a
/// `Sources/**/Lint.Rule.*.*.swift` file, whose concatenated text does not
/// begin `[<rule_id>] <citation>: `, is flagged. The rule does NOT verify
/// the citation's existence — only the message-text shape.
extension Lint.Rule {
  public static let `diagnostic message format` = Lint.Rule(
    id: "diagnostic message format",
    default: .warning,
    controls: [
      .init(
        id: "diagnostic message format malformed",
        source: "enum Demo { static let message = \"prefer typed throws\" }",
        path: "Sources/Controls/Lint.Rule.Demo.Example.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "diagnostic message format conforming",
        source: "enum Demo { static let message = \"[try_optional] "
          + "[API-ERR-001]: prefer typed throws\" }",
        path: "Sources/Controls/Lint.Rule.Demo.Example.swift",
        expectation: .clean
      ),
      .init(
        id: "diagnostic message format helper scope",
        source: "enum Demo { static let message = \"prefer typed throws\" }",
        path: "Sources/Controls/Helper.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // Scope per the Python's detection scope: `Sources/**/
      // Lint.Rule.<Module>.<Name>.swift` only — the institute's
      // linter-rule authoring sites. Rule-runner infrastructure, output
      // formatters, the registry, the namespace placeholder
      // `Lint.Rule.<Module>.swift` (fewer than four dotted segments) and
      // hidden directories are all out of scope.
      guard namingDiagnosticFormatIsLintRuleSource(source.file.filePath) else {
        return []
      }
      let visitor = NamingDiagnosticFormatVisitor(
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
internal let namingDiagnosticFormatMessage: Swift.String =
  "[diagnostic message format] [API-NAME-009]: `static let message` does "
  + "not follow the educational-diagnostic format `[<rule_id>] <citation>: "
  + "<description>`. The leading bracket carries the rule id (snake_case or "
  + "kebab-case), the citation is a skill rule ID (`[API-ERR-001]`), a "
  + "feedback-memory filename (`feedback_no_try_optional`) or a research-doc "
  + "path (`Research/typed-throws-rationale.md`), and a `: ` separates the "
  + "citation from the description."

/// Returns true when `filePath` is a linter-rule authoring site per the
/// Python's `iter_lint_rule_sources`: a whole directory segment `Sources`
/// somewhere on the path, a basename matching `Lint.Rule.*.*.swift` with at
/// least four dotted stem segments, and no hidden (`.`-prefixed) path
/// segment.
internal func namingDiagnosticFormatIsLintRuleSource(_ filePath: Swift.String) -> Swift.Bool {
  let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
  guard let filename = components.last else { return false }
  guard components.dropLast().contains("Sources") else { return false }
  guard !components.contains(where: { $0.hasPrefix(".") }) else { return false }
  guard filename.hasSuffix(".swift") else { return false }
  let stem = Swift.String(filename.dropLast(".swift".count))
  guard stem.hasPrefix("Lint.Rule.") else { return false }
  // A rule file has 4+ dot-separated stem segments
  // (`Lint.Rule.Foo.Bar`); the namespace shape `Lint.Rule.Foo` has 3.
  return stem.filter { $0 == "." }.count >= 3
}

/// Returns true when `text` begins `[<rule_id>] <citation>: ` per the
/// Python's `FORMAT_RE`: `^\[[a-z_][\w-]*\]\s+\S[^:]*?\s*:\s`. The rule id
/// is snake_case or kebab-case (first character lowercase or underscore,
/// then word characters or hyphens — no spaces); the citation segment is
/// non-empty, colon-free, and terminated by `:` plus whitespace.
internal func namingDiagnosticFormatMatches(_ text: Swift.String) -> Swift.Bool {
  var bytes = text.utf8.map(Byte.init)[...]
  // `^\[`
  guard bytes.first == 0x5B else { return false }
  bytes = bytes.dropFirst()
  // `[a-z_]`
  guard let first = bytes.first,
    (first >= 0x61 && first <= 0x7A) || first == 0x5F
  else { return false }
  bytes = bytes.dropFirst()
  // `[\w-]*`
  while let byte = bytes.first, namingDiagnosticFormatIsWord(byte) || byte == 0x2D {
    bytes = bytes.dropFirst()
  }
  // `\]`
  guard bytes.first == 0x5D else { return false }
  bytes = bytes.dropFirst()
  // `\s+`
  guard let space = bytes.first, namingDiagnosticFormatIsWhitespace(space)
  else { return false }
  while let byte = bytes.first, namingDiagnosticFormatIsWhitespace(byte) {
    bytes = bytes.dropFirst()
  }
  // `\S` — the citation's first character exists and is non-whitespace
  // (guaranteed non-whitespace by the loop above) and is not the `:`
  // terminator itself, which would leave the citation empty.
  guard let citationFirst = bytes.first, citationFirst != 0x3A else { return false }
  bytes = bytes.dropFirst()
  // `[^:]*?\s*:\s` — scan to the first `:`; it must be followed by
  // whitespace. (`[^:]*?` is colon-free by construction when scanning to
  // the FIRST colon; `\s*` permits trailing whitespace inside it.)
  while let byte = bytes.first, byte != 0x3A {
    bytes = bytes.dropFirst()
  }
  guard bytes.first == 0x3A else { return false }
  bytes = bytes.dropFirst()
  guard let after = bytes.first else { return false }
  return namingDiagnosticFormatIsWhitespace(after)
}

private func namingDiagnosticFormatIsWord(_ byte: Byte) -> Swift.Bool {
  (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A)
    || (byte >= 0x30 && byte <= 0x39) || byte == 0x5F
}

private func namingDiagnosticFormatIsWhitespace(_ byte: Byte) -> Swift.Bool {
  // The Python's `\s`: space, tab, newline, carriage return, form feed,
  // vertical tab.
  byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    || byte == 0x0B || byte == 0x0C
}

internal final class NamingDiagnosticFormatVisitor: SyntaxVisitor {
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

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    // `static let message` — the Python's MESSAGE_DECL requires the
    // `static` modifier, the `let` keyword and the exact name `message`
    // (an optional type annotation is permitted).
    guard node.bindingSpecifier.tokenKind == .keyword(.let) else { return .visitChildren }
    guard node.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) })
    else { return .visitChildren }
    for binding in node.bindings {
      guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
        pattern.identifier.text == "message",
        let initializer = binding.initializer
      else { continue }
      // The Python only matches an initializer that BEGINS with a string
      // literal; an initializer of any other shape (a call, a reference,
      // an array) is out of the mechanical check's scope and skipped.
      guard let concatenated = namingDiagnosticFormatConcatenatedLiteral(initializer.value)
      else { continue }
      if !namingDiagnosticFormatMatches(concatenated) {
        let position = binding.pattern.positionAfterSkippingLeadingTrivia
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
            identifier: "diagnostic message format",
            message: namingDiagnosticFormatMessage
          )
        )
      }
    }
    return .visitChildren
  }
}

/// Concatenates a string literal or a `+`-chain of string literals into the
/// message text the format check runs against, mirroring the Python's
/// literal-chain capture and its `\n`/`\t`/`\"`/`\\` unescaping. Returns
/// nil when the expression is not composed of string literals — the
/// declaration is then outside the mechanical check's scope, exactly as the
/// Python's regex would fail to match it.
internal func namingDiagnosticFormatConcatenatedLiteral(
  _ expression: ExprSyntax
) -> Swift.String? {
  if let literal = expression.as(StringLiteralExprSyntax.self) {
    return namingDiagnosticFormatLiteralText(literal)
  }
  if let sequence = expression.as(SequenceExprSyntax.self) {
    // Unfolded `a + b + c`: elements alternate operand, operator, operand…
    // Every operand must be a string literal and every operator `+` for
    // the chain to be in scope; the leading operand must be a literal
    // regardless (the Python anchors on `= "` and captures the chain of
    // literals that follows).
    var parts: [Swift.String] = []
    for (index, element) in sequence.elements.enumerated() {
      if index % 2 == 0 {
        guard let literal = element.as(StringLiteralExprSyntax.self) else {
          // A non-literal operand ends the Python's capture; the leading
          // literals already collected still get checked when the FIRST
          // operand was a literal.
          return parts.isEmpty ? nil : parts.joined()
        }
        parts.append(namingDiagnosticFormatLiteralText(literal))
      } else {
        guard let binaryOperator = element.as(BinaryOperatorExprSyntax.self),
          binaryOperator.operator.text == "+"
        else {
          return parts.isEmpty ? nil : parts.joined()
        }
      }
    }
    return parts.isEmpty ? nil : parts.joined()
  }
  // Defensive: folded-tree shape, per the pack's dual-shape convention.
  if let infix = expression.as(InfixOperatorExprSyntax.self) {
    guard let binaryOperator = infix.operator.as(BinaryOperatorExprSyntax.self),
      binaryOperator.operator.text == "+",
      let left = namingDiagnosticFormatConcatenatedLiteral(infix.leftOperand)
    else { return nil }
    guard let right = namingDiagnosticFormatConcatenatedLiteral(infix.rightOperand) else {
      return left
    }
    return left + right
  }
  return nil
}

/// A literal's text with the Python's four escape sequences resolved. An
/// interpolation segment contributes its source text verbatim — the format
/// prefix this rule checks is a fixed literal in every conforming message,
/// so interpolated tails cannot rescue a malformed prefix.
private func namingDiagnosticFormatLiteralText(
  _ literal: StringLiteralExprSyntax
) -> Swift.String {
  var text = ""
  for segment in literal.segments {
    switch segment {
    case .stringSegment(let stringSegment):
      // Same four replacements, in the same order, as the Python.
      text += stringSegment.content.text
        .replacing("\\n", with: "\n")
        .replacing("\\t", with: "\t")
        .replacing("\\\"", with: "\"")
        .replacing("\\\\", with: "\\")

    case .expressionSegment(let expressionSegment):
      text += expressionSegment.trimmedDescription
    }
  }
  return text
}
