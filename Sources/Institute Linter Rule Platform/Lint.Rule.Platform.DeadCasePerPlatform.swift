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

/// Wave 4 (mechanization-program) — public enum whose cases enumerate
/// platforms (POSIX / Windows, or UTF8 / UTF16) is the dead-case anti-
/// pattern in disguise.
///
/// Citation: `[PATTERN-056]` (implementation skill, the patterns note).
extension Lint.Rule {
  public static let `dead case per platform` = Lint.Rule(
    id: "dead case per platform",
    default: .warning,
    controls: [
      .init(
        id: "dead case per platform public platform cases",
        source: "public enum Encoding { case posix; case windows }",
        path: "Sources/Platform Core/PlatformEncoding.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "dead case per platform domain alternatives",
        source: "public enum URLScheme { case http; case https }",
        path: "Sources/Platform Core/DomainAlternatives.swift",
        expectation: .clean
      ),
      .init(
        id: "dead case per platform internal boundary",
        source: "internal enum Encoding { case posix; case windows }",
        path: "Sources/Platform Core/InternalEncoding.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      let visitor = PlatformDeadCasePerPlatformVisitor(
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
internal let platformDeadCasePerPlatformMessage: Swift.String =
  "[dead case per platform] [PATTERN-056]: public enum cases "
  + "enumerate platforms (POSIX / Windows or UTF8 / UTF16). Consumer "
  + "`switch` statements get N-1 dead branches per platform. Replace "
  + "with the ecosystem's existing platform-conditional typealias "
  + "(`Path.Char`, `String.Char`) for storage; add a local `Encoding` "
  + "typealias for decoder calls."

internal let platformDeadCasePerPlatformPlatformPairs: [Swift.Set<Swift.String>] = [
  ["posix", "windows"],
  ["utf8", "utf16"],
  ["linux", "darwin"],
  ["linux", "darwin", "windows"],
  ["linux", "darwin", "windows", "freebsd"],
  ["macos", "linux"],
  ["macos", "windows"],
]

/// A subset test (#21 defect 4), not exact-set equality: `{ case posix,
/// windows, unknown }` still enumerates the POSIX/Windows platform split
/// even with an extra non-platform case, and exact equality evaded it.
/// Accepted consequence, recorded deliberately: a genuinely open
/// platform-identity enum (`enum OperatingSystem { case linux, darwin,
/// windows, freebsd, android }`) now fires too — that is the shape this
/// rule exists for, it is `.warning`, and the author has a suppression
/// directive.
internal func platformDeadCasePerPlatformMatchesPlatformPair(_ cases: [Swift.String]) -> Swift.Bool
{
  let lower = Swift.Set(cases.map { $0.lowercased() })
  for pair in platformDeadCasePerPlatformPlatformPairs {
    if pair.isSubset(of: lower) {
      return true
    }
  }
  return false
}

internal final class PlatformDeadCasePerPlatformVisitor: SyntaxVisitor {
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

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    guard platformIsPublicAPIEffective(Syntax(node), modifiers: node.modifiers) else {
      return .visitChildren
    }
    var caseNames: [Swift.String] = []
    for member in Lint.Syntax.Conditional.members(node.memberBlock) {
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
        continue
      }
      for element in caseDecl.elements {
        caseNames.append(element.name.text)
      }
    }
    guard caseNames.count >= 2 else {
      return .visitChildren
    }
    guard platformDeadCasePerPlatformMatchesPlatformPair(caseNames) else {
      return .visitChildren
    }
    let location = converter.location(
      for: node.enumKeyword.positionAfterSkippingLeadingTrivia
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
        identifier: "dead case per platform",
        message: platformDeadCasePerPlatformMessage
      )
    )
    return .visitChildren
  }
}
