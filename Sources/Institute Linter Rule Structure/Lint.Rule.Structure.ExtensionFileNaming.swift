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

/// Extension-only files name their base type plus a discriminator:
/// `Array.Dynamic+Cursor.Protocol.swift` (non-standard-library
/// conformance addition — standard-library conformances such as
/// `Sendable` stay in `Array.Dynamic.swift` itself),
/// `Array.Dynamic where Element Comparable.swift` (constraint-
/// discriminated extension), or `Array.Dynamic+Iteration.swift`
/// (`+<Topic>` for member-only extensions).
///
/// Citation: `[API-IMPL-007]`. Adjudicated on
/// swift-institute-linter-rules#6 (ruling D2, 2026-07-30); implemented
/// per swift-institute-linter-rules#9. Every design decision below
/// mirrors that issue verbatim.
///
/// The rule's surface is a source file under `Sources/` whose
/// top-level declarations are exclusively `extension` declarations
/// (zero primary nominal types — `[API-IMPL-006]`'s surface,
/// including its cascade suppression, is excluded here). For each
/// such file:
///
/// 1. Every extension must extend the same dotted base-type path;
///    otherwise the rule fires once — a mixed-base extension file has
///    no lawful name.
/// 1a. Else, if EVERY extension adds only standard-library
///    conformances (`extension Custom: Sendable {}`,
///    `extension Custom: Hashable { … }`), the file has no lawful
///    name at all: standard-library conformances stay in the type's
///    own file, `Custom.swift`, as extensions directly under the type
///    declaration. The rule fires once with a relocation message.
///    Standard-library conformances never count as conformances for
///    step 2 — `<Base>+<Conformance>` is reserved for protocols
///    outside the standard library. The set is
///    `structureStdlibProtocolNames` (`Lint.Rule.Structure.Shared.swift`).
/// 2. Else, if any extension adds a (non-standard-library)
///    conformance, the required basename is
///    `<Base>+<Conformance>.swift`, naming one of the added
///    conformances (matching ANY added conformance satisfies the rule
///    — a conditional conformance restated on a conditional extension,
///    `extension T: P where …`, still classifies here, not under 3).
/// 3. Else, if any extension carries a `where` clause, the required
///    basename is the `<Base> where <discriminator>.swift` shape: the
///    segment after ` where ` must be non-empty and the basename must
///    begin with `<Base> where `. The discriminator's exact text is
///    repository-owned and not further constrained.
/// 4. Else (member-only extensions), the basename is either
///    `<Base>+<Topic>.swift` for members owned by the extended type,
///    or `<Owner>+<Base>.swift` for a conversion initializer owned by
///    its input domain. The latter is accepted only when an initializer
///    parameter has the exact dotted `<Owner>` type path. This preserves
///    names such as `Algebra.Group+Algebra.Magma.swift` for
///    `extension Algebra.Magma { init(_: Algebra.Group<Element>) }`.
///
/// The rule fires when the basename does not satisfy the classified
/// shape.
///
/// Excluded from the surface: files with any top-level primary
/// nominal type (`[API-IMPL-006]`'s surface); `Tests`, `Experiments`,
/// and `Examples` path scope.
///
/// The diagnostic is located at the file's first extension
/// declaration. The canonical fix is a rename to the classified
/// shape; no source edit.
extension Lint.Rule {
  public static let `extension file naming` = Lint.Rule(
    id: "extension file naming",
    default: .warning,
    controls: [
      .init(
        id: "extension file naming missing topic",
        source: "extension Array.Dynamic { func iterate() {} }",
        path: "Sources/Structure Core/Array.Dynamic.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "extension file naming member topic",
        source: "extension Array.Dynamic { func iterate() {} }",
        path: "Sources/Structure Core/Array.Dynamic+Iteration.swift",
        expectation: .clean
      ),
      .init(
        id: "extension file naming conversion owner",
        source: "extension Algebra.Magma { init(_ group: Algebra.Group<Element>) {} }",
        path: "Sources/Algebra Group/Algebra.Group+Algebra.Magma.swift",
        expectation: .clean
      ),
      .init(
        id: "extension file naming stdlib conformance relocation",
        source: "extension Array.Dynamic: Sendable {}",
        path: "Sources/Structure Core/Array.Dynamic+Sendable.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "extension file naming test scope",
        source: "extension Array.Dynamic { func iterate() {} }",
        path: "Tests/Structure Tests/Array.Dynamic.swift",
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
      return structureExtensionFileNamingFindings(
        path: path,
        source: source.file,
        severity: severity,
        converter: source.converter,
        tree: source.tree
      )
    }
  )
}

private func structureExtensionFileNamingFindings(
  path: Swift.String,
  source: Source.File,
  severity: Diagnostic.Severity,
  converter: SourceLocationConverter,
  tree: SourceFileSyntax
) -> [Diagnostic.Record] {
  let filename: Swift.String
  if let slashIndex = path.lastIndex(of: "/") {
    filename = Swift.String(path[path.index(after: slashIndex)...])
  } else {
    filename = path
  }
  guard filename.hasSuffix(".swift") else { return [] }
  let basename = Swift.String(filename.dropLast(".swift".count))

  let collector = StructureExtensionFileNamingCollector()
  collector.walk(tree)

  // Excluded from the surface — [API-IMPL-006]'s surface (any
  // top-level primary nominal type present).
  guard !collector.hasPrimaryType else { return [] }
  guard let first = collector.extensions.first else { return [] }

  let location = converter.location(for: first.extendedType.positionAfterSkippingLeadingTrivia)

  func record(_ message: Swift.String) -> [Diagnostic.Record] {
    [
      Diagnostic.Record(
        location: Source.Location(
          fileID: source.fileID,
          filePath: source.filePath,
          line: location.line,
          column: location.column
        ),
        severity: severity,
        identifier: "extension file naming",
        message: message
      )
    ]
  }

  // Mixed-base detection: every extension's extended-type must resolve to
  // the same base key. `structureDottedName` returns
  // nil for anything that isn't an identifier/member/metatype type (sugar
  // and tuple forms — `[Int]`, `Int?`, …); fall back to the type's own
  // trimmed text so those extensions still contribute a distinguishing
  // key instead of being silently dropped from the set (which could let
  // a genuinely mixed-base file pass `bases.count == 1` undetected, or —
  // when it was the FIRST extension that fell through — exempt the
  // entire file even though the remaining extensions are misnamed).
  let bases = Swift.Set(
    collector.extensions.map { structureExtensionFileNamingBaseKey($0.extendedType) }
  )
  let base = structureExtensionFileNamingBaseKey(first.extendedType)
  guard bases.count == 1 else {
    return record(
      structureExtensionFileNamingMixedBaseMessage(basename: basename, bases: bases)
    )
  }

  // Standard-library conformances have no extension-file shape: they
  // live in the type's own file. A file consisting solely of them
  // fires the relocation message, and they are dropped from the
  // conformance classification below so a `Custom+Sendable.swift`
  // never passes as a lawful `<Base>+<Conformance>` name.
  if collector.extensions.allSatisfy(structureIsStdlibOnlyConformanceExtension) {
    return record(
      structureExtensionFileNamingStdlibConformanceMessage(basename: basename, base: base)
    )
  }
  let conformances = collector.extensions.flatMap { extensionDecl -> [Swift.String] in
    guard let clause = extensionDecl.inheritanceClause else { return [] }
    return clause.inheritedTypes.compactMap {
      structureDottedName(of: $0.type).map(Lint.Syntax.Identifier.unescaped)
    }
    .filter { !structureIsStdlibConformance($0) }
  }
  let hasWhere = collector.extensions.contains { $0.genericWhereClause != nil }

  if !conformances.isEmpty {
    let conformancePrefix = "\(base)+"
    if basename.hasPrefix(conformancePrefix) {
      let candidate = Swift.String(basename.dropFirst(conformancePrefix.count))
      // Accept the leaf component (and any dotted suffix) of a
      // module-qualified conformance spelling, not just the verbatim
      // fully-qualified path — `extension Array.Dynamic: Swift.Sequence`
      // names its conformance `Swift.Sequence`, and the canonical
      // `Array.Dynamic+Sequence.swift` must not be rejected in favor of
      // `Array.Dynamic+Swift.Sequence.swift`, a name no repository uses.
      if conformances.contains(where: {
        structureExtensionFileNamingConformanceMatches(
          candidate: candidate,
          conformance: $0
        )
      }) {
        return []
      }
    }
    return record(
      structureExtensionFileNamingConformanceMessage(
        basename: basename,
        base: base,
        conformance: conformances[0]
      )
    )
  }

  if hasWhere {
    let prefix = "\(base) where "
    if basename.hasPrefix(prefix), basename.count > prefix.count {
      return []
    }
    return record(structureExtensionFileNamingWhereMessage(basename: basename, base: base))
  }

  // Member-only: `<Base>+<Topic>`.
  let prefix = "\(base)+"
  if basename.hasPrefix(prefix), basename.count > prefix.count {
    return []
  }
  if structureExtensionFileNamingIsConversionOwned(
    basename: basename,
    extendedBase: base,
    extensions: collector.extensions
  ) {
    return []
  }
  return record(structureExtensionFileNamingTopicMessage(basename: basename, base: base))
}

@usableFromInline
internal func structureExtensionFileNamingMixedBaseMessage(
  basename: Swift.String,
  bases: Swift.Set<Swift.String>
) -> Swift.String {
  let sorted = bases.sorted().joined(separator: "', '")
  return "[extension file naming] [API-IMPL-007]: extension file '\(basename).swift' mixes "
    + "extensions on different base types ('\(sorted)'); a mixed-base extension file has "
    + "no lawful name — split into one file per base type."
}

@usableFromInline
internal func structureExtensionFileNamingStdlibConformanceMessage(
  basename: Swift.String,
  base: Swift.String
) -> Swift.String {
  "[extension file naming] [API-IMPL-007]: extension file '\(basename).swift' adds only "
    + "standard-library conformances; those stay in the type's own file '\(base).swift' as "
    + "extensions directly under the type declaration (e.g. `extension \(base): Sendable {}`), "
    + "never in a '+<Conformance>' sibling file — move the extension(s) there"
}

@usableFromInline
internal func structureExtensionFileNamingConformanceMessage(
  basename: Swift.String,
  base: Swift.String,
  conformance: Swift.String
) -> Swift.String {
  "[extension file naming] [API-IMPL-007]: extension file '\(basename).swift' must be named "
    + "'\(base)+\(conformance).swift' for the conformance it adds"
}

@usableFromInline
internal func structureExtensionFileNamingWhereMessage(
  basename: Swift.String,
  base: Swift.String
) -> Swift.String {
  "[extension file naming] [API-IMPL-007]: extension file '\(basename).swift' must use the "
    + "'\(base) where <discriminator>.swift' shape"
}

@usableFromInline
internal func structureExtensionFileNamingTopicMessage(
  basename: Swift.String,
  base: Swift.String
) -> Swift.String {
  "[extension file naming] [API-IMPL-007]: extension file '\(basename).swift' must carry a "
    + "'+<Topic>' member group (e.g. '\(base)+Topic.swift') or, for a conversion "
    + "initializer, use '<Owner>+\(base).swift' with a parameter of that owner type"
}

private func structureExtensionFileNamingIsConversionOwned(
  basename: Swift.String,
  extendedBase: Swift.String,
  extensions: [ExtensionDeclSyntax]
) -> Swift.Bool {
  let suffix = "+\(extendedBase)"
  guard basename.hasSuffix(suffix), basename.count > suffix.count else { return false }
  let owner = Swift.String(basename.dropLast(suffix.count))

  for extensionDecl in extensions {
    for member in extensionDecl.memberBlock.members {
      guard let initializer = member.decl.as(InitializerDeclSyntax.self) else { continue }
      for parameter in initializer.signature.parameterClause.parameters
      where structureDottedName(of: parameter.type) == owner
      {
        return true
      }
    }
  }
  return false
}

/// Walks top-level statements only, collecting every top-level
/// `extension` declaration and noting whether the file also declares
/// any top-level primary nominal type (`[API-IMPL-006]`'s surface,
/// including a type nested via a top-level extension shell — the same
/// predicate `single type per file` and `file name nested path` use).
private final class StructureExtensionFileNamingCollector: SyntaxVisitor {
  var extensions: [ExtensionDeclSyntax] = []
  var hasPrimaryType: Swift.Bool = false

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
    for item in Lint.Syntax.Conditional.statements(node.statements) {
      guard case .decl(let decl) = item.item else { continue }
      if let extensionDecl = decl.as(ExtensionDeclSyntax.self) {
        extensions.append(extensionDecl)
        for member in extensionDecl.memberBlock.members
        where structureExtensionFileNamingIsPrimaryTypeDecl(member.decl) {
          hasPrimaryType = true
        }
        continue
      }
      if structureExtensionFileNamingIsPrimaryTypeDecl(decl) {
        hasPrimaryType = true
      }
    }
    return .skipChildren
  }
}

/// Resolves an extended-type to a base key for mixed-base detection: the
/// dotted path when resolvable, or the type's own trimmed source text
/// otherwise (sugar / tuple / other forms `structureDottedName`
/// doesn't resolve). Every extension MUST contribute a key — silently
/// dropping unresolvable ones (via `compactMap`) can hide a genuinely
/// mixed-base file, or exempt the whole file when it was the first
/// extension whose extended type fell through.
private func structureExtensionFileNamingBaseKey(_ type: TypeSyntax) -> Swift.String {
  structureDottedName(of: type) ?? type.trimmedDescription
}

/// Returns true if `candidate` (the basename tail after `<Base>+`) names
/// `conformance` — either verbatim, or as the leaf component (or any
/// dotted suffix) of a module-qualified conformance spelling. A
/// conformance recorded as `Swift.Sequence` must accept the basename tail
/// `Sequence`, not just `Swift.Sequence`.
private func structureExtensionFileNamingConformanceMatches(
  candidate: Swift.String,
  conformance: Swift.String
) -> Swift.Bool {
  if candidate == conformance { return true }
  return conformance.hasSuffix(".\(candidate)")
}

private func structureExtensionFileNamingIsPrimaryTypeDecl(_ decl: DeclSyntax) -> Swift.Bool {
  decl.is(StructDeclSyntax.self)
    || decl.is(ClassDeclSyntax.self)
    || decl.is(EnumDeclSyntax.self)
    || decl.is(ActorDeclSyntax.self)
    || decl.is(ProtocolDeclSyntax.self)
}
