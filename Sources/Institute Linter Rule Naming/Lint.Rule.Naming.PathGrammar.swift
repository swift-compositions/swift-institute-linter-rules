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

/// Path naming grammar (swift-institute-linter-rules#65, principal
/// directive 2026-08-09): the directory and file names a source file
/// sits under follow the ratified Nest.Name grammar, mechanically.
///
/// **Owner decision recorded (Axiom 9, one predicate, one owner):** the
/// Nest.Name directory ruling of 2026-08-06 assigned directory
/// validation to the Workspace/Institute validator family. The #65
/// audit (2026-08-10) found no such validator implemented in the
/// institute coordinator sources; the gap closes here, in the linter's
/// Naming family, because every linted file already carries its path —
/// the per-file grammar is expressible without filesystem access, and
/// the compound-word predicate's single owner (`namingWordIsCompound`)
/// lives in this module. The manifest↔filesystem *correspondence* half
/// (declared `path:` vs target name) is `manifest naming grammar`'s.
///
/// Two predicates, one rule:
///
/// 1. **Directory segments**: every directory segment strictly after
///    the first `Sources` or `Tests` segment of the file's path must be
///    a spaced Nest.Name form — space-separated words, none a
///    concatenated compound by the shared predicate (brand tokens such
///    as `GitHub` exempt there). `Institute Architecture CLI` passes;
///    `InstituteArchitectureCLI` fires. Segments whose name ends in
///    `.docc` (documentation catalogues, tool-named) and the canonical
///    snapshot-reference directory `.snapshots` are exempt by
///    predicate — their orthography is fixed by the owning tool or
///    Institute policy, not by the Nest.Name grammar. Other spellings
///    in the snapshot-directory family, including legacy
///    `__Snapshots__`, fire with `.snapshots` as the canonical fix.
/// 2. **File basename dot segments**: when the file declares at least
///    one primary nominal type (directly at top level or nested in a
///    top-level extension — the same notion `file name nested path`
///    [API-IMPL-006] uses, including the [RULE-EXEMPT-7] visitor-
///    subclass exclusion), each `.`-separated segment of the basename
///    (after dropping `.swift`, any `+` conformance suffix, and any
///    ` where ` discriminator) must be non-compound. This is the
///    residual class 006 and `compound type name` [API-NAME-001] leave
///    open in composition: a file such as
///    `InstituteArchitectureCLI.Command.swift` whose compound OUTER
///    segment names a type declared in another file passes 006 (the
///    name matches the path) and never reaches [API-NAME-001] in this
///    file (the compound type is not declared here).
///
/// **File-name surface audit (the #65 enumeration):** the declared-type
/// case is already owned in composition — [API-IMPL-006] forces
/// basename == declared dotted path and [API-NAME-001] rejects the
/// compound declaration, so `InstituteArchitectureCLI.swift` declaring
/// that type fires today. Predicate 2 closes the
/// declared-elsewhere-segment gap. The remaining residue, recorded and
/// deliberately NOT policed: extension-only files with descriptive
/// basenames (the linter rule packs' own
/// `Lint.Rule.Naming.CompoundType.swift` house shape) declare no
/// primary type to anchor the grammar; their segments reference no
/// declaration this file can see, and a zero from this rule is not
/// evidence about them.
///
/// The diagnostic is located at the start of the file (there is no
/// in-file syntax to anchor a path fact to). The canonical fix is a
/// directory or file rename; no source edit.
///
/// Citation: `swift-institute-linter-rules#65`; Nest.Name directory
/// ruling 2026-08-06; Goal #94.
extension Lint.Rule {
  public static let `path name grammar` = Lint.Rule(
    id: "path name grammar",
    default: .warning,
    controls: [
      .init(
        id: "path name grammar concatenated directory",
        source: "struct Command {}",
        path: "Sources/InstituteArchitectureCLI/Command.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "path name grammar spaced directory",
        source: "struct Command {}",
        path: "Sources/Institute Architecture CLI/Command.swift",
        expectation: .clean
      ),
      .init(
        id: "path name grammar out of surface",
        source: "struct Command {}",
        path: "Plugins/BadPluginName/Plugin.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      namingPathGrammarFindings(
        source: source.file,
        severity: severity,
        tree: source.tree
      )
    }
  )
}

/// Directory segments exempt by predicate: tool-owned orthography.
internal func namingPathGrammarDirectoryIsExempt(_ segment: Swift.String) -> Swift.Bool {
  if segment.hasSuffix(".docc") { return true }
  if segment == ".snapshots" { return true }
  return false
}

/// Whether a directory uses a noncanonical spelling from the
/// snapshot-reference directory family. Punctuation and case are
/// normalized only to recognize that bounded family; unrelated target
/// names such as `Example Snapshot Tests` remain on the Nest.Name path.
internal func namingPathGrammarSnapshotDirectoryIsInvalid(
  _ segment: Swift.String
) -> Swift.Bool {
  guard segment != ".snapshots" else { return false }
  return segment.filter { $0.isLetter }.lowercased() == "snapshots"
}

/// The compound words in one path or basename segment: the segment is
/// split on single spaces and each word consulted against the shared
/// compound predicate.
internal func namingPathGrammarCompoundWords(in segment: Swift.String) -> [Swift.String] {
  segment.split(separator: " ").map(Swift.String.init).filter(namingWordIsCompound)
}

@usableFromInline
internal func namingPathGrammarDirectoryMessage(
  segment: Swift.String,
  words: [Swift.String]
) -> Swift.String {
  "[path name grammar]: directory '\(segment)' contains concatenated "
    + "word\(words.count == 1 ? "" : "s") "
    + words.map { "'\($0)'" }.joined(separator: ", ")
    + " — directory names use the spaced Nest.Name form "
    + "(e.g. `Institute Architecture CLI`); rename the directory"
}

@usableFromInline
internal func namingPathGrammarSnapshotDirectoryMessage(
  segment: Swift.String
) -> Swift.String {
  "[path name grammar]: snapshot-reference directory '\(segment)' uses a "
    + "noncanonical spelling — rename the directory to `.snapshots`"
}

@usableFromInline
internal func namingPathGrammarBasenameMessage(
  segment: Swift.String,
  basename: Swift.String
) -> Swift.String {
  "[path name grammar]: file name segment '\(segment)' in "
    + "'\(basename).swift' is a concatenated compound — file names are "
    + "the declared type's dotted Nest.Name path "
    + "(e.g. `Institute.Architecture.CLI.swift`); rename the file"
}

internal func namingPathGrammarFindings(
  source: Source.File,
  severity: Diagnostic.Severity,
  tree: SourceFileSyntax
) -> [Diagnostic.Record] {
  let path = source.filePath
  let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(Swift.String.init)
  guard parts.count >= 2 else { return [] }
  guard let rootIndex = parts.firstIndex(where: { $0 == "Sources" || $0 == "Tests" })
  else { return [] }
  // Manifests are `manifest naming grammar`'s surface, and a nested
  // test manifest's own path never reaches here (it is the package
  // root's child, not a Sources/Tests descendant with segments).
  guard let filename = parts.last else { return [] }
  guard filename.hasSuffix(".swift") else { return [] }

  var records: [Diagnostic.Record] = []
  func emit(_ message: Swift.String) {
    records.append(
      Diagnostic.Record(
        location: Source.Location(
          fileID: source.fileID,
          filePath: source.filePath,
          line: 1,
          column: 1
        ),
        severity: severity,
        identifier: "path name grammar",
        message: message
      )
    )
  }

  // Predicate 1 — directory segments after the Sources/Tests root.
  let firstDirectory = parts.index(after: rootIndex)
  let fileIndex = parts.index(before: parts.endIndex)
  for segment in parts[firstDirectory..<fileIndex] {
    if namingPathGrammarSnapshotDirectoryIsInvalid(segment) {
      emit(namingPathGrammarSnapshotDirectoryMessage(segment: segment))
      continue
    }
    guard !namingPathGrammarDirectoryIsExempt(segment) else { continue }
    let words = namingPathGrammarCompoundWords(in: segment)
    if !words.isEmpty {
      emit(namingPathGrammarDirectoryMessage(segment: segment, words: words))
    }
  }

  // Predicate 2 — basename dot segments, anchored on a declared
  // primary nominal type.
  var basename = Swift.String(filename.dropLast(".swift".count))
  if let plusIndex = basename.firstIndex(of: "+") {
    basename = Swift.String(basename[basename.startIndex..<plusIndex])
  }
  if let whereRange = basename.range(of: " where ") {
    basename = Swift.String(basename[basename.startIndex..<whereRange.lowerBound])
  }
  let collector = NamingPathGrammarPrimaryTypeCollector()
  collector.walk(tree)
  guard collector.declaresPrimaryType else { return records }
  for segment in basename.split(separator: ".").map(Swift.String.init) {
    if namingWordIsCompound(segment) {
      emit(
        namingPathGrammarBasenameMessage(
          segment: segment,
          basename: Swift.String(filename.dropLast(".swift".count))
        )
      )
    }
  }
  return records
}

/// Walks top-level statements only, answering whether the file declares
/// at least one primary nominal type — `struct`, `enum`, `actor`,
/// `protocol`, or a `class` outside the SwiftSyntax visitor family
/// ([RULE-EXEMPT-7]) — directly at top level or nested one level inside
/// a top-level extension. Mirrors [API-IMPL-006]'s primary-type notion.
internal final class NamingPathGrammarPrimaryTypeCollector: SyntaxVisitor {
  var declaresPrimaryType: Swift.Bool = false

  init() { super.init(viewMode: .sourceAccurate) }

  private func isPrimary(_ decl: DeclSyntax) -> Swift.Bool {
    if let classDecl = decl.as(ClassDeclSyntax.self) {
      return !Naming.Visitor.extends(classDecl.inheritanceClause)
    }
    return decl.is(StructDeclSyntax.self)
      || decl.is(EnumDeclSyntax.self)
      || decl.is(ActorDeclSyntax.self)
      || decl.is(ProtocolDeclSyntax.self)
  }

  override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
    for item in Lint.Syntax.Conditional.statements(node.statements) {
      guard case .decl(let decl) = item.item else { continue }
      if let extensionDecl = decl.as(ExtensionDeclSyntax.self) {
        for member in extensionDecl.memberBlock.members where isPrimary(member.decl) {
          declaresPrimaryType = true
          return .skipChildren
        }
        continue
      }
      if isPrimary(decl) {
        declaresPrimaryType = true
        return .skipChildren
      }
    }
    return .skipChildren
  }
}
