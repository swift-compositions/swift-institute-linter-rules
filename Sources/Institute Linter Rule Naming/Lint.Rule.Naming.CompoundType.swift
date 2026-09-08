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

/// Wave 1 (mechanization-program) — compound type names at declaration site.
///
/// Citation: `[API-NAME-001]` (code-surface skill — Nest.Name pattern).
extension Lint.Rule {
  public static let `compound type name` = Lint.Rule(
    id: "compound type name",
    default: .warning,
    controls: [
      .init(
        id: "compound type name public compound",
        source: "public struct FileDirectory {}",
        path: "Sources/Naming Core/CompoundType.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "compound type name single token",
        source: "public struct Directory {}",
        path: "Sources/Naming Core/SingleTokenType.swift",
        expectation: .clean
      ),
      .init(
        id: "compound type name spec namespace",
        source: "public enum RFC_4122 {}",
        path: "Sources/Naming Core/SpecNamespace.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // Scan-scope gate (BEFORE the walk), symmetric with
      // `compound identifier`: a SwiftPM manifest is build configuration,
      // not API surface. See `namingIsPackageManifest`.
      guard !namingIsPackageManifest(source.file.filePath) else { return [] }
      let visitor = NamingCompoundTypeVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

private let namingCompoundTypeMessage: Swift.String =
  "[compound type name] [API-NAME-001]: types MUST use the `Nest.Name` "
  + "pattern. Compound type names like `FileDirectoryWalk` or "
  + "`DirectoryWalk` are forbidden — use the nested form "
  + "(`File.Directory.Walk`). Acronyms (`URL`, `UUID`, `IO`) are "
  + "permitted as single-word names; spec-namespace forms with "
  + "underscores (`RFC_4122`, `ISO_9945`) are exempt per "
  + "`[API-NAME-003]`. `package`-scope declarations and macro decls "
  + "are exempt; `fileprivate`/`private` type declarations including "
  + "members whose effective visibility is reduced by an enclosing "
  + "fileprivate/private type are exempt per "
  + "the API-NAME-002 private-surface-applicability note "
  + "(symmetric extension of the 2026-05-11 [API-NAME-002] amendment "
  + "— consumer-observable surface is the rule's intent and "
  + "fileprivate/private types have none even within the module). "
  + "Stdlib-method-mirror type names that elevate a Swift.Sequence "
  + "(or adjacent) method name to a namespace are exempt per "
  + "`[API-NAME-003]` — see `namingCompoundTypeStdlibMethodMirrorCitations` "
  + "in this rule's source for the citation set. Brand tokens whose "
  + "internal capitals are brand/spec orthography (`GitHub`, `OAuth`, "
  + "`IPv4`, …) are exempt per the #16 Option C ledger — see "
  + "`namingCompoundTypeBrandTokenCitations`; propose additions there "
  + "with the authority that fixes the spelling."

/// Compound type names that mirror a Swift-stdlib method name and
/// elevate it to a namespace at the institute's iteration / collection
/// layer. The institute's lazy-iteration adapters (`Sequence.Map`,
/// `Sequence.Filter`, `Sequence.Reduce`, `Sequence.Drop`, `Sequence.Prefix`)
/// use single-word type names corresponding to stdlib's single-word
/// methods. For stdlib's compound method names — `compactMap`,
/// `flatMap`, `forEach` — the institute's matching adapter type
/// inherits the compound spelling rather than fragmenting the spec-
/// mirror correspondence into `Sequence.Compact.Map` etc.
///
/// Citation: `[API-NAME-003]` (spec-mirroring exemption).
///
/// Each entry cites the specific Swift.Sequence (or adjacent) method
/// whose name the type elevates. Adding an entry without a citation
/// makes the exemption indefensible at review time.
private let namingCompoundTypeStdlibMethodMirrorCitations: [Swift.String: Swift.String] = [
  "CompactMap": "Swift.Sequence.compactMap(_:) / Swift.Optional.compactMap(_:)",
  "FlatMap": "Swift.Sequence.flatMap(_:) / Swift.Optional.flatMap(_:)",
  "ForEach": "Swift.Sequence.forEach(_:)",
  "AllSatisfy": "Swift.Sequence.allSatisfy(_:)",
]

/// Brand tokens whose canonical spelling carries internal capitals that
/// the word-boundary heuristic misreads as a compound name (#16 Option C
/// ledger, Entries III.a/III.b DECISION 2026-07-23). A brand token is a
/// SINGLE word whose orthography is fixed by the brand or specification
/// that owns it — `GitHub` is not `Git` + `Hub` any more than `OAuth` is
/// `O` + `Auth`. Firing on these forces the ecosystem's own canonical
/// naming (`GitHub.Owner.ID`, `GitHub.HTTP.OAuth`) into per-site disables.
///
/// Mirrors the `namingCompoundTypeStdlibMethodMirrorCitations` /
/// `namingCompoundSwiftNativeIdiomCitations` mechanism: each entry cites
/// the authority that fixes the spelling; adding an entry without a
/// citation is indefensible at review time. Entries match the full type
/// name token only — `GitHubClient` (a genuine compound) still fires.
private let namingCompoundTypeBrandTokenCitations: [Swift.String: Swift.String] = [
  "GitHub":
    "github.com brand orthography — ecosystem canonical `GitHub.Owner.ID` (swift-github-standard)",
  "OAuth": "RFC 6749 (The OAuth 2.0 Authorization Framework) — spec's own token spelling",
  "IPv4": "RFC 791 — protocol-version orthography (`IPv4.Address`, swift-rfc-791)",
  "IPv6": "RFC 8200 — protocol-version orthography",
  "PostgreSQL": "postgresql.org brand orthography",
]

internal final class NamingCompoundTypeVisitor: SyntaxVisitor {
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

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    check(name: node.name, modifiers: node.modifiers, syntax: Syntax(node))
    return .visitChildren
  }
  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    // Exempt per [RULE-EXEMPT-7] (syntax-visitor-subclass): the
    // SwiftSyntax convention names visitor subclasses
    // `<Subject>Visitor` (e.g. `CardinalConstructorVisitor`,
    // `CompoundVisitor`), which trips compound-name even though
    // the suffix is dictated by the framework's idiom. Helper
    // lives in `Lint.Rule.Naming.Shared.swift`. See
    // the rule-exemptions skill.
    if Naming.Visitor.extends(node.inheritanceClause) {
      return .visitChildren
    }
    check(name: node.name, modifiers: node.modifiers, syntax: Syntax(node))
    return .visitChildren
  }
  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    check(name: node.name, modifiers: node.modifiers, syntax: Syntax(node))
    return .visitChildren
  }
  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    check(name: node.name, modifiers: node.modifiers, syntax: Syntax(node))
    return .visitChildren
  }
  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    check(name: node.name, modifiers: node.modifiers, syntax: Syntax(node))
    return .visitChildren
  }

  // Macros are exempt per [API-NAME-001] — descend without checking.
  override func visit(_: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
    .visitChildren
  }

  private func check(name token: TokenSyntax, modifiers: DeclModifierListSyntax, syntax: Syntax) {
    guard !hasPackageModifier(modifiers) else { return }
    // Visibility-scope exemption: fileprivate / private type decls
    // have no consumer-observable surface even within the module.
    // The walk-up captures effective visibility (a nested type
    // inside a fileprivate enclosing type is effectively
    // fileprivate even when its own modifier list is empty).
    // Symmetric with the [API-NAME-002] visibility-scope amendment
    // (2026-05-11, Option B) — see
    // the API-NAME-002 private-surface-applicability note.
    if Naming.hasFileprivateOrPrivateEffective(syntax, modifiers: modifiers) {
      return
    }
    // Backtick-escape exemption: see `Naming.isBackticked` for the
    // full rationale. A backticked type-name token (e.g.,
    // `` struct `compound identifier Tests` `` for a @Suite scaffold,
    // or `` struct `Edge Case` ``) signals the author opted out of
    // the Nest.Name convention this rule enforces — typically for
    // narrative @Suite type names per [SWIFT-TEST-002].
    if Naming.isBackticked(token) { return }
    let text = token.text
    guard isCompoundTypeIdentifier(text) else { return }
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
        identifier: "compound type name",
        message: namingCompoundTypeMessage
      )
    )
  }

  private func hasPackageModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
    for modifier in modifiers {
      if modifier.name.tokenKind == .keyword(.package) {
        return true
      }
    }
    return false
  }

  private func isCompoundTypeIdentifier(_ name: Swift.String) -> Bool {
    namingWordIsCompound(name)
  }
}

/// The single owner of the compound-word predicate (one predicate, one
/// owner — #65): returns true when `name` is a concatenation of two or
/// more words by the internal-capital heuristic, after the stdlib-
/// method-mirror ([API-NAME-003]) and brand-token (#16 Option C)
/// exemptions. Shared by `compound type name` (declaration surface) and
/// the #65 grammar rules (`manifest naming grammar`, `path name
/// grammar` — manifest / directory / file-name surfaces).
internal func namingWordIsCompound(_ name: Swift.String) -> Bool {
  // Stdlib-method-mirror exemption per [API-NAME-003]: type names
  // that elevate a Swift.Sequence (or adjacent) compound method
  // name to a namespace inherit the compound spelling.
  if namingCompoundTypeStdlibMethodMirrorCitations[name] != nil {
    return false
  }
  // Brand-token exemption per #16 Option C Entries III.a/III.b: the
  // token's internal capitals are brand/spec orthography, not word
  // boundaries. Exact-match only.
  if namingCompoundTypeBrandTokenCitations[name] != nil {
    return false
  }
  // Spec-namespace forms (`RFC_4122`, `ISO_9945`) — exempt.
  if name.contains("_") { return false }
  // Empty / single-char names — degenerate, not compound.
  guard name.count >= 2 else { return false }
  // Must start with uppercase to be a type identifier (sanity).
  let chars = Array(name)
  guard chars[0].isUppercase else { return false }
  // Word-boundary count.
  var words = 1
  var i = 1
  while i < chars.count {
    let previous = chars[chars.index(before: i)]
    let curr = chars[i]
    let nextIndex = chars.index(after: i)
    let next: Swift.Character? = nextIndex < chars.endIndex ? chars[nextIndex] : nil
    if curr.isUppercase {
      // lowercase → uppercase: word boundary (FooBar)
      if previous.isLowercase {
        words += 1
      } else if previous.isUppercase, let next, next.isLowercase {
        // uppercase → uppercase → lowercase: acronym → word
        // boundary (IOError ⇒ IO + Error at the E).
        words += 1
      }
    }
    if words >= 2 { return true }
    i += 1
  }
  return false
}
