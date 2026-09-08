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

/// Wave 2b finalization (2026-05-10) — `Error`-conforming types MUST
/// NOT also suppress `Copyable`.
///
/// Citation: `[MEM-COPY-002]` (memory-safety skill, the ownership note).
///
/// `Swift.Error` requires `Copyable` (the protocol's existential
/// boxing relies on the value being copyable). A type declared
/// `~Copyable` cannot conform to `Error`. The fix is to use a
/// non-throwing outcome type carrying the move-only value, or to
/// keep the error type `Copyable` and refer to the move-only value
/// through a copyable handle.
extension Lint.Rule {
  public static let `noncopyable error` = Lint.Rule(
    id: "noncopyable error",
    default: .warning,
    controls: [
      .init(
        id: "noncopyable error conformance",
        source: "struct Failure: Error, ~Copyable {}",
        path: "Sources/Memory Core/NoncopyableError.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "noncopyable error copyable",
        source: "struct Failure: Error {}",
        path: "Sources/Memory Core/CopyableError.swift",
        expectation: .clean
      ),
      .init(
        id: "noncopyable error nonerror",
        source: "struct Token: ~Copyable {}",
        path: "Sources/Memory Core/NoncopyableToken.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // `~Copyable` can only be suppressed on the primary declaration,
      // but `Error` can be added by a same-file extension (#25 defect
      // 5) — a pre-pass collects every extension's inherited leaf
      // names, keyed by the extended type's dotted path, so the
      // visitor can check "declaration clause OR any same-file
      // extension".
      let collector = MemoryErrorNoncopyableExtensionCollector(viewMode: .sourceAccurate)
      collector.walk(source.tree)
      let visitor = MemoryErrorNoncopyableVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter,
        extensionConformances: collector.conformances
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

@usableFromInline
internal let memoryErrorNoncopyableMessage: Swift.String =
  "[noncopyable error] [MEM-COPY-002]: `Error`-conforming types MUST NOT "
  + "suppress `Copyable`. `Swift.Error`'s existential boxing requires `Copyable`. "
  + "A `~Copyable` Error type fails to compile or to interoperate with the "
  + "throwing protocol surface. Use a non-throwing `Outcome` enum (`.success`/"
  + "`.failure`) carrying the move-only value, or hold the move-only state in "
  + "a copyable handle and reference it from the error."

/// Collects, for each `extension <Name>` in the file, the union of its
/// inheritance-clause leaf names, keyed by the extension's own
/// (unresolved) extended-type text. Used so `conformsToError` can be
/// satisfied by a same-file `extension E: Error {}` sibling to `struct
/// E: ~Copyable {}`, not only by the declaration's own clause (#25
/// defect 5).
internal final class MemoryErrorNoncopyableExtensionCollector: SyntaxVisitor {
  var conformances: [Swift.String: Swift.Set<Swift.String>] = [:]

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard let clause = node.inheritanceClause else { return .visitChildren }
    let key = node.extendedType.trimmedDescription
    var leaves = conformances[key] ?? []
    for inherited in clause.inheritedTypes {
      var current = inherited.type
      while let attributed = current.as(AttributedTypeSyntax.self) {
        current = attributed.baseType
      }
      if let identifier = current.as(IdentifierTypeSyntax.self) {
        leaves.insert(identifier.name.text)
      }
      if let member = current.as(MemberTypeSyntax.self) {
        leaves.insert(member.name.text)
      }
    }
    conformances[key] = leaves
    return .visitChildren
  }
}
