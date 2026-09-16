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

/// A file's basename equals the declared type's full nested dotted path
/// (e.g. `Array.Dynamic.Iterator.swift` for `Array.Dynamic.Iterator`).
///
/// Citation: `[API-IMPL-006]`. Adjudicated on
/// swift-institute-linter-rules#6 (ruling D1, 2026-07-30); implemented
/// per swift-institute-linter-rules#8. Every design decision below
/// mirrors that issue verbatim.
///
/// The rule's surface is a source file under `Sources/` whose top-level
/// declarations declare exactly one primary nominal type (`struct`,
/// `enum`, `class`, `actor`, or `protocol`), whether declared directly
/// at top level or as the single nominal declaration nested inside a
/// top-level `extension Outer { … }` shell. The primary type's dotted
/// path is its full nesting chain: the enclosing extension's dotted
/// extended-type path, plus any enclosing namespace-enum shells, plus
/// its own name. The rule fires when the basename does not equal that
/// dotted path exactly (case-sensitive, `.`-separated).
///
/// Excluded from the surface (not exemptions — out of scope by
/// predicate):
/// - Basenames matching an `[API-IMPL-007]` shape (a `+` segment, or a
///   ` where ` clause discriminator) — 007's surface exclusively.
/// - Files with zero primary nominal types (extension-only files —
///   007's surface) or more than one top-level primary type (the
///   one-type-per-file rule's surface — `[API-IMPL-005]` /
///   `single type per file`).
/// - `Tests`, `Experiments`, and `Examples` path scope, mirroring
///   `single type per file`'s exclusion.
///
/// Cascade suppression (D1, the proven predicate from the
/// diagnostic-precedence record, adopted verbatim): when the file also
/// contains top-level extensions other than the one nesting the
/// primary type, this rule suppresses its finding only when exact
/// parsing proves that EVERY one of those other top-level extensions
/// carries a conformance clause or a `where` clause discriminator —
/// the canonical `[API-IMPL-007]` repair for those extensions
/// necessarily moves the file into 007's own excluded shape. A single
/// bare, member-only extension among them defeats the suppression and
/// this rule still fires. So does an extension adding only
/// standard-library conformances (`extension Custom: Sendable {}`):
/// those stay in the type's own file by design, so no 007 repair
/// applies and the rename is the only fix.
///
/// Known false positives prevented by resolution, not exemption:
/// - The hoisted-`Protocol` idiom (a module-scope protocol declared
///   directly at top level, paired with a top-level extension
///   containing `public typealias \`Protocol\` = <the protocol>`)
///   resolves to the owning extension's dotted path plus `.Protocol`,
///   not the hoisted spelling — matching the real precedent
///   (`Array.Protocol.swift` declaring `protocol __ArrayProtocol` at
///   top level alongside `extension __Array { typealias \`Protocol\`
///   = __ArrayProtocol }`).
/// - A namespace-enum shell declaring exactly one nested type (no
///   cases, only typealiases besides the one nested type — the same
///   shape `single type namespace` flags) resolves through to the
///   nested type's path: `enum A { enum B { struct C {} } }` resolves
///   to `A.B.C`, not `A`.
///
/// The diagnostic is located at the primary type's own name (so
/// editors surface it in-file). The canonical fix is a file rename;
/// no source edit.
extension Lint.Rule {
  public static let `file name nested path` = Lint.Rule(
    id: "file name nested path",
    default: .warning,
    controls: [
      .init(
        id: "file name nested path mismatched basename",
        source: "enum Array { struct Dynamic {} }",
        path: "Sources/Structure Core/Array.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "file name nested path matching basename",
        source: "enum Array { struct Dynamic {} }",
        path: "Sources/Structure Core/Array.Dynamic.swift",
        expectation: .clean
      ),
      .init(
        id: "file name nested path test scope",
        source: "enum Array { struct Dynamic {} }",
        path: "Tests/Structure Tests/Array.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      let path = source.file.filePath
      // The rule's stated surface is "a source file under `Sources/`"
      // (doc comment above); the predicate previously only excluded
      // Tests/Experiments/Examples, leaving Benchmarks/, Plugins/,
      // Snippets/, and the package root in scope by accident.
      guard path.hasPrefix("Sources/") || path.contains("/Sources/") else {
        return []
      }
      for excluded in ["Tests", "Experiments", "Examples"] {
        if path == excluded
          || path.hasPrefix("\(excluded)/")
          || path.contains("/\(excluded)/")
        {
          return []
        }
      }
      guard let slashIndex = path.lastIndex(of: "/") else {
        return structureFileNameNestedPathFindings(
          basename: path,
          source: source.file,
          severity: severity,
          converter: source.converter,
          tree: source.tree
        )
      }
      let filename = Swift.String(path[path.index(after: slashIndex)...])
      return structureFileNameNestedPathFindings(
        basename: filename,
        source: source.file,
        severity: severity,
        converter: source.converter,
        tree: source.tree
      )
    }
  )
}

private func structureFileNameNestedPathFindings(
  basename filename: Swift.String,
  source: Source.File,
  severity: Diagnostic.Severity,
  converter: SourceLocationConverter,
  tree: SourceFileSyntax
) -> [Diagnostic.Record] {
  guard filename.hasSuffix(".swift") else { return [] }
  let basename = Swift.String(filename.dropLast(".swift".count))

  // Excluded from the surface — [API-IMPL-007]'s shapes exclusively.
  if basename.contains("+") || basename.contains(" where ") { return [] }

  let collector = Collector()
  collector.walk(tree)

  guard collector.primaryTypes.count == 1 else { return [] }
  let primary = collector.primaryTypes[0]

  let resolvedOwnPath = structureFileNameNestedPathResolve(primary.node)
  var dottedPath =
    primary.extensionPrefix.isEmpty
    ? resolvedOwnPath
    : "\(primary.extensionPrefix).\(resolvedOwnPath)"

  // Hoisted-`Protocol` idiom: a top-level protocol paired with a
  // top-level extension's `typealias \`Protocol\` = <thisProtocol>`
  // resolves to the extension's dotted path + ".Protocol", not the
  // hoisted spelling.
  if let protocolDecl = primary.node.as(ProtocolDeclSyntax.self) {
    let protocolName = protocolDecl.name.text
    for extensionDecl in collector.topLevelExtensions {
      guard
        let carrierPath = structureDottedName(
          of: extensionDecl.extendedType
        )
      else { continue }
      for member in extensionDecl.memberBlock.members {
        guard let alias = member.decl.as(TypeAliasDeclSyntax.self) else { continue }
        guard Lint.Syntax.Identifier.unescaped(alias.name.text) == "Protocol" else {
          continue
        }
        guard
          let aliasedName = structureDottedName(of: alias.initializer.value)
        else { continue }
        guard aliasedName == protocolName else { continue }
        dottedPath = "\(carrierPath).Protocol"
      }
    }
  }

  guard basename != dottedPath else { return [] }

  // Cascade suppression (D1): every OTHER top-level extension (not the
  // one nesting the primary type, if any) must carry a conformance or
  // where-clause discriminator to suppress this finding. An extension
  // adding only standard-library conformances (`extension Custom:
  // Sendable {}`) does NOT discriminate: its home IS the type's own
  // file, so 007's repair never moves it out and the rename this rule
  // prescribes remains the only fix. See `structureStdlibProtocolNames`.
  let wrappingPosition = primary.wrappingExtension?.position
  let others = collector.topLevelExtensions.filter { $0.position != wrappingPosition }
  if !others.isEmpty {
    let allDiscriminated = others.allSatisfy { extensionDecl in
      let hasConformance =
        extensionDecl.inheritanceClause.map { !$0.inheritedTypes.isEmpty } ?? false
      let hasWhere = extensionDecl.genericWhereClause != nil
      let staysWithType =
        !hasWhere && structureIsStdlibOnlyConformanceExtension(extensionDecl)
      return (hasConformance || hasWhere) && !staysWithType
    }
    if allDiscriminated { return [] }
  }

  let location = converter.location(for: primary.namePosition)
  return [
    Diagnostic.Record(
      location: Source.Location(
        fileID: source.fileID,
        filePath: source.filePath,
        line: location.line,
        column: location.column
      ),
      severity: severity,
      identifier: "file name nested path",
      message: structureFileNameNestedPathMessage(basename: basename, dottedPath: dottedPath)
    )
  ]
}

@usableFromInline
internal func structureFileNameNestedPathMessage(
  basename: Swift.String,
  dottedPath: Swift.String
) -> Swift.String {
  "[file name nested path] [API-IMPL-006]: file name '\(basename).swift' does not match "
    + "the declared type's nested path '\(dottedPath)'; rename to '\(dottedPath).swift'"
}

/// Resolves a namespace-enum-shell chain to its innermost leaf path:
/// `enum A { enum B { struct C {} } }` resolves to `A.B.C`. A shell is
/// a caseless enum whose only members (besides any number of
/// typealiases) are exactly one nested type declaration — the same
/// shape `single type namespace` flags as an anti-pattern.
private func structureFileNameNestedPathResolve(_ node: DeclSyntax) -> Swift.String {
  guard let enumDecl = node.as(EnumDeclSyntax.self) else {
    return structureFileNameNestedPathOwnName(node) ?? ""
  }
  var nestedTypes: [DeclSyntax] = []
  for member in enumDecl.memberBlock.members {
    if member.decl.is(EnumCaseDeclSyntax.self) {
      // Has cases — not a shell.
      return enumDecl.name.text
    }
    if member.decl.is(TypeAliasDeclSyntax.self) { continue }
    if structureFileNameNestedPathIsPrimaryTypeDecl(member.decl) {
      nestedTypes.append(member.decl)
      continue
    }
    // Any other member (function, property, ...) disqualifies the shell.
    return enumDecl.name.text
  }
  guard nestedTypes.count == 1 else {
    return enumDecl.name.text
  }
  return "\(enumDecl.name.text).\(structureFileNameNestedPathResolve(nestedTypes[0]))"
}

private func structureFileNameNestedPathIsPrimaryTypeDecl(_ declaration: DeclSyntax) -> Swift.Bool {
  declaration.is(StructDeclSyntax.self)
    || declaration.is(ClassDeclSyntax.self)
    || declaration.is(EnumDeclSyntax.self)
    || declaration.is(ActorDeclSyntax.self)
    || declaration.is(ProtocolDeclSyntax.self)
}

private func structureFileNameNestedPathOwnName(_ node: DeclSyntax) -> Swift.String? {
  if let d = node.as(StructDeclSyntax.self) { return d.name.text }
  if let d = node.as(ClassDeclSyntax.self) { return d.name.text }
  if let d = node.as(ActorDeclSyntax.self) { return d.name.text }
  if let d = node.as(ProtocolDeclSyntax.self) { return d.name.text }
  if let d = node.as(EnumDeclSyntax.self) { return d.name.text }
  return nil
}

/// Returns true for a candidate "primary type" nominal declaration —
/// `struct`/`class`/`enum`/`actor`/`protocol` — EXCLUDING a `class` that
/// subclasses the SwiftSyntax visitor family (`SyntaxVisitor`,
/// `SyntaxAnyVisitor`, `SyntaxRewriter`) per [RULE-EXEMPT-7]
/// (syntax-visitor-subclass).
///
/// The rule-file house shape pairs a public `extension Lint.Rule { public
/// static let \`x\` = … }` (the file's real, public API surface) with a
/// private `internal final class FooVisitor: SyntaxVisitor { … }`
/// implementation helper. Without this exemption the collector resolves
/// the private visitor as the file's "primary type" and demands a rename
/// to its (non-public, implementation-detail) name — wrong in every file
/// of that shape. `minimal type body` already applies the same
/// [RULE-EXEMPT-7] exemption via `structureExtendsSyntaxVisitor`; this
/// rule now shares it rather than resolving the private helper as if it
/// were the file's declared type.
internal func isPrimary(_ decl: DeclSyntax) -> Swift.Bool {
  if let classDecl = decl.as(ClassDeclSyntax.self) {
    if structureExtendsSyntaxVisitor(classDecl.inheritanceClause) { return false }
    return true
  }
  return decl.is(StructDeclSyntax.self)
    || decl.is(EnumDeclSyntax.self)
    || decl.is(ActorDeclSyntax.self)
    || decl.is(ProtocolDeclSyntax.self)
}

/// One top-level primary nominal type found by the collector, together
/// with the enclosing extension's dotted prefix (empty if declared
/// directly at top level) and the wrapping extension node itself (used
/// to exclude it from cascade suppression's "other extensions" set).
internal func position(of node: DeclSyntax) -> AbsolutePosition {
  if let d = node.as(StructDeclSyntax.self) { return d.name.positionAfterSkippingLeadingTrivia }
  if let d = node.as(ClassDeclSyntax.self) { return d.name.positionAfterSkippingLeadingTrivia }
  if let d = node.as(EnumDeclSyntax.self) { return d.name.positionAfterSkippingLeadingTrivia }
  if let d = node.as(ActorDeclSyntax.self) { return d.name.positionAfterSkippingLeadingTrivia }
  if let d = node.as(ProtocolDeclSyntax.self) { return d.name.positionAfterSkippingLeadingTrivia }
  return node.positionAfterSkippingLeadingTrivia
}
