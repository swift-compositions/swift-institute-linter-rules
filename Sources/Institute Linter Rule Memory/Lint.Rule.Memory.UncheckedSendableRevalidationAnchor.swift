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

/// Compiler-limitation-citing `@unchecked Sendable` MUST carry a
/// revalidation anchor in the declaration's leading trivia. The anchor's
/// three institute markers — `WHY:`, `WHEN TO REMOVE:`, `TRACKING:` —
/// make a compiler-limitation justification falsifiable on toolchain
/// bumps; without them the justification ages silently into folklore.
///
/// Citation: `[MEM-SEND-006]` (memory-safety skill, the concurrency note).
///
/// Detection algorithm:
///
/// 1. Locate `@unchecked Sendable` on the inheritance clause of any
///    type-decl form (struct, class, enum, actor, extension).
/// 2. Scan the declaration's full leading-trivia line/block comments
///    for compiler-limitation indicators (a curated regex set —
///    `compiler …`, `until Swift`, `Sendable workaround`, `Category D`,
///    `@_rawLayout`, `WORKAROUND`).
/// 3. If no compiler-limitation indicator surfaces, the conformance is
///    out of scope for this rule (justification doesn't cite a compiler
///    limitation); return clean.
/// 4. If at least one indicator surfaces, the conformance is in scope;
///    require all three institute anchor markers (`WHY:`,
///    `WHEN TO REMOVE:`, `TRACKING:`) in the candidate trivia text.
///    Emit a finding naming the missing marker(s) when any are absent.
///
/// The rule does NOT validate marker content (no URL check on
/// TRACKING, no path check on WHEN TO REMOVE). Marker presence is the
/// invariant; content discipline lives in the rule body and is enforced
/// by review.
///
/// Wording-only carve-out: the skill body's literal anchor format
/// example prescribes a `WORKAROUND FOR COMPILER LIMITATION` header,
/// but the institute's actual ecosystem practice uses the three-marker
/// anchor without that strict header. The rule mechanizes practice
/// (the three markers) per Examples-as-authoritative; the Statement
/// amendment to align example with practice is queued in the
/// [MEM-SEND-006] pilot's Phase 8 outcome record.
extension Lint.Rule {
  public static let `unchecked sendable revalidation anchor` = Lint.Rule(
    id: "unchecked sendable revalidation anchor",
    default: .warning,
    controls: [
      .init(
        id: "unchecked sendable revalidation anchor incomplete",
        source: "// WHY: Category D — compiler workaround.\nextension Container: @unchecked Sendable {}",
        path: "Sources/Memory Core/IncompleteRevalidationAnchor.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "unchecked sendable revalidation anchor complete",
        source: "// WHY: Category D — compiler workaround.\n// WHEN TO REMOVE: When structural inference lands.\n// TRACKING: issue-1.\nextension Container: @unchecked Sendable {}",
        path: "Sources/Memory Core/CompleteRevalidationAnchor.swift",
        expectation: .clean
      ),
      .init(
        id: "unchecked sendable revalidation anchor semantic",
        source: "// Callers externally synchronize access.\nextension Container: @unchecked Sendable {}",
        path: "Sources/Memory Core/SemanticSendable.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      let visitor = MemoryUncheckedSendableRevalidationAnchorVisitor(
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
internal let memoryUncheckedSendableRevalidationAnchorMessage: Swift.String =
  "[unchecked sendable revalidation anchor] [MEM-SEND-006]: "
  + "`@unchecked Sendable` whose justification cites a compiler limitation "
  + "MUST carry a revalidation anchor in the declaration's leading trivia. "
  + "Required markers: `WHY:` (the limitation), `WHEN TO REMOVE:` (the "
  + "toolchain / compiler-fix trigger), `TRACKING:` (the experiment path or "
  + "issue link). Without these, the justification ages into folklore as "
  + "compilers fix the underlying limitation. If the conformance is NOT "
  + "compiler-limitation-justified, drop the limitation-citing language from "
  + "the comment block — this rule fires only when limitation indicators "
  + "(`compiler`, `until Swift`, `Sendable workaround`, `Category D`, "
  + "`@_rawLayout`, `WORKAROUND`) are present in the declaration's full "
  + "leading trivia (not just the line immediately above it)."

internal final class MemoryUncheckedSendableRevalidationAnchorVisitor: SyntaxVisitor {
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

  // MARK: - Attribute / Sendable detection
  //
  // Shape mirrors `UncheckedSendableCategorized` — `@unchecked` lives
  // on the `AttributedTypeSyntax` wrapping the inherited type in the
  // conformance clause. The inherited type is `Sendable` (or
  // `Swift.Sendable`).

  private func hasUncheckedAttribute(_ inherited: InheritedTypeSyntax) -> Bool {
    if let attributed = inherited.type.as(AttributedTypeSyntax.self) {
      for attribute in attributed.attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        if attr.attributeName.trimmedDescription == "unchecked" {
          return true
        }
      }
    }
    return false
  }

  private func isSendableInherited(_ inherited: InheritedTypeSyntax) -> Bool {
    var current = inherited.type
    while let attributed = current.as(AttributedTypeSyntax.self) {
      current = attributed.baseType
    }
    if let identifier = current.as(IdentifierTypeSyntax.self) {
      return identifier.name.text == "Sendable"
    }
    if let member = current.as(MemberTypeSyntax.self) {
      return member.name.text == "Sendable"
    }
    return false
  }

  // MARK: - Trivia collection
  //
  // The relevant trivia is the FULL leading trivia of the
  // declaration's first token. Concatenate every `lineComment` /
  // `blockComment` / `docLineComment` / `docBlockComment` piece into
  // one candidate string; the indicator + anchor matchers operate on
  // that string. Comments separated from the declaration by blank
  // lines are still part of the leading trivia and count.

  private func collectCommentText(_ trivia: Trivia) -> Swift.String {
    var collected: Swift.String = ""
    for piece in trivia {
      switch piece {
      case .lineComment(let text),
        .blockComment(let text),
        .docLineComment(let text),
        .docBlockComment(let text):
        collected.append(text)
        collected.append("\n")

      default:
        continue
      }
    }
    return collected
  }

  // MARK: - Compiler-limitation indicators
  //
  // The curated indicator set captures the institute's idioms for
  // justifying `@unchecked Sendable` against a compiler limitation
  // (as distinct from semantic responsibility, performance,
  // type-erasure, etc., which are out of scope for this rule). The
  // matching is case-insensitive and uses plain substring checks —
  // there's no NSRegularExpression dependency in the linter layer.

  private func hasCompilerLimitationIndicator(_ text: Swift.String) -> Bool {
    let lower = text.lowercased()

    // `compiler` paired with limitation verbs ("cannot/can't prove",
    // "doesn't infer", "limitation", "won't").
    if lower.contains("compiler") {
      let verbs = [
        "cannot", "can't", "cant",
        "doesn't", "doesnt",
        "won't", "wont",
        "limitation",
        "infer",
        "prove",
      ]
      for verb in verbs where lower.contains(verb) {
        return true
      }
    }

    // Direct idioms.
    if lower.contains("until swift") { return true }
    if lower.contains("@_rawlayout") { return true }
    // #25 nit: a bare "workaround" check subsumes "sendable
    // workaround" — any string containing the longer phrase also
    // contains "workaround"; the two-line form was dead redundancy.
    if lower.contains("workaround") { return true }

    // Institute audit-findings Category-letter scheme. Category D
    // tags structural Sendable workarounds (compiler-limitation
    // justification — the rule's literal scope). Categories A/B/C
    // are semantic-responsibility cases (synchronized, single-thread,
    // raw-pointer-controlled) per [MEM-SAFE-024] and documented via
    // `## Safety Invariant` doc sections, NOT WHY/WHEN/TRACKING
    // markers. Only Category D matches.
    //
    // Provenance: Phase 6 iteration (2026-05-15) on the [MEM-SEND-006]
    // pilot — first pass scoped to A-D over-fired on Ownership.Transfer
    // family (Category A, synchronized) and similar non-compiler-
    // limitation annotations.
    if lower.contains("category d") {
      return true
    }

    return false
  }

  // MARK: - Anchor markers
  //
  // The three institute markers — `WHY:`, `WHEN TO REMOVE:`,
  // `TRACKING:`. Matching is case-insensitive on the marker keyword
  // and tolerant of leading `// `, whitespace, or `/// ` doc-comment
  // prefixes. Marker order is not enforced; multi-line continuation
  // (`// WHY: foo\n// WHY: bar`) is fine as long as the keyword
  // appears at least once.

  fileprivate struct AnchorPresence {
    var why: Bool = false
    var whenToRemove: Bool = false
    var tracking: Bool = false
  }

  private func anchorPresence(_ text: Swift.String) -> AnchorPresence {
    // #25 nit: corrected stale doc — the three markers below are
    // three independent `.contains` calls against the same lowered
    // haystack, so no check-before-check ordering exists or is
    // required; each marker's presence is decided on its own.
    let lower = text.lowercased()
    return AnchorPresence(
      why: lower.contains("why:"),
      whenToRemove: lower.contains("when to remove:"),
      tracking: lower.contains("tracking:")
    )
  }

  // MARK: - Emission

  private func emit(at inherited: InheritedTypeSyntax, missing: [Swift.String]) {
    let location = converter.location(for: inherited.positionAfterSkippingLeadingTrivia)
    let missingList: Swift.String
    if missing.isEmpty {
      missingList = ""
    } else {
      missingList = " Missing: " + missing.joined(separator: ", ") + "."
    }
    matches.append(
      Diagnostic.Record(
        location: Source.Location(
          fileID: source.fileID,
          filePath: source.filePath,
          line: location.line,
          column: location.column
        ),
        severity: severity,
        identifier: "unchecked sendable revalidation anchor",
        message: memoryUncheckedSendableRevalidationAnchorMessage + missingList
      )
    )
  }

  // MARK: - Shared check helper

  private func check(
    declaration: any DeclSyntaxProtocol,
    inheritanceClause: InheritanceClauseSyntax?
  ) {
    guard let inheritanceClause else { return }

    // Identify the @unchecked Sendable inherited slot, if any.
    var triggers: [InheritedTypeSyntax] = []
    for inherited in inheritanceClause.inheritedTypes {
      guard isSendableInherited(inherited) else { continue }
      guard hasUncheckedAttribute(inherited) else { continue }
      triggers.append(inherited)
    }
    guard !triggers.isEmpty else { return }

    // Walk the declaration's full leading trivia. The relevant
    // trivia attaches to the declaration's FIRST token — which is
    // the first attribute, modifier, or decl keyword depending on
    // shape. SwiftSyntax's `node.leadingTrivia` resolves to that
    // first-token trivia.
    let trivia = declaration.leadingTrivia
    let commentText = collectCommentText(trivia)

    // If the candidate text doesn't cite a compiler limitation,
    // the conformance is out of scope for this rule.
    guard hasCompilerLimitationIndicator(commentText) else { return }

    // Check the three anchor markers.
    let presence = anchorPresence(commentText)
    guard !presence.isComplete else { return }

    // Emit per trigger (a single declaration normally has one
    // @unchecked Sendable slot; pluralizing supports edge cases
    // where multiple Sendable variants appear).
    for trigger in triggers {
      emit(at: trigger, missing: presence.missingMarkers)
    }
  }

  // MARK: - Decl visitors

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    check(declaration: node, inheritanceClause: node.inheritanceClause)
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    check(declaration: node, inheritanceClause: node.inheritanceClause)
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    check(declaration: node, inheritanceClause: node.inheritanceClause)
    return .visitChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    check(declaration: node, inheritanceClause: node.inheritanceClause)
    return .visitChildren
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    check(declaration: node, inheritanceClause: node.inheritanceClause)
    return .visitChildren
  }
}

extension MemoryUncheckedSendableRevalidationAnchorVisitor.AnchorPresence {
  var isComplete: Bool { why && whenToRemove && tracking }

  var missingMarkers: [Swift.String] {
    var missing: [Swift.String] = []
    if !why { missing.append("WHY:") }
    if !whenToRemove { missing.append("WHEN TO REMOVE:") }
    if !tracking { missing.append("TRACKING:") }
    return missing
  }
}
