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

/// R5 — `__unchecked:` argument label appearing at a call site.
///
/// Distinguishes call-site uses (anti-pattern per [CONV-016] tier 5) from
/// declaration-site uses (legitimate extension-init machinery per [CONV-001]).
/// The distinction is structural: call-site arguments parse as
/// `LabeledExprSyntax` (a `LabeledExprSyntax.label` token whose text equals
/// `__unchecked`); declaration-site parameters parse as
/// `FunctionParameterSyntax` (a `FunctionParameterSyntax.firstName` token).
/// This rule visits only the former.
///
/// References:
/// - the cardinal/ordinal/vector enforcement design note
///   §"R5. `__unchecked:` use at call sites" — the original DEFER rationale.
/// - the SwiftSyntax-based custom-linter investigation note
///   §"Q3 — Deferred AST-rule unblocking matrix" — R5 is unblocked by this tool.
///
/// ## The [CONV-001] extension-init bottom-out — ruled disposition
///
/// Ruled 2026-08-01 (#38, from the 2026-08-01 fleet sweep): the sanctioned
/// same-package bottom-out is mechanized for the shape [CONV-001] actually
/// names — a call sitting directly in an `extension` initializer's body
/// that constructs that extension's own type. All three conjuncts are
/// syntax at the site (the enclosing `init`, its `extension` member
/// context, and the callee naming the extended type).
///
/// Every other same-package bottom-out is **accept-as-warning**, not a
/// predicate exemption (the [IMPL-089] precedent): a nominal-type-body
/// initializer, a private factory function, or an extension init
/// constructing a sibling type is syntactically indistinguishable from an
/// ordinary consumer bypass. The per-site
/// `// swift-linter:disable:next unchecked call site` with a `// REASON:`
/// continuation is the correct instrument there.
///
/// Whole-run self-suppression: when the run's own sources declare a
/// `Lint.Brand.vocabulary` type at namespace root, the run
/// owns the brand and `__unchecked:` is the owner's own boundary
/// ([CONV-001]) — the rule returns no findings for the whole run. Retires
/// the per-package `.excluding(rules:)` stopgap.
extension Lint.Rule {
  public static let `unchecked call site` = Lint.Rule(
    id: "unchecked call site",
    default: .warning,
    controls: [
      .init(
        id: "unchecked call site consumer bypass",
        source: "let value = Cardinal(__unchecked: raw)",
        path: "Sources/Unchecked Consumer/ConsumerBypass.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "unchecked call site declaration parameter",
        source: "struct Cardinal { init(__unchecked _: Int) {} }",
        path: "Sources/Unchecked Consumer/DeclarationParameter.swift",
        expectation: .clean
      ),
      .init(
        id: "unchecked call site extension initializer bottom out",
        source: "extension Cardinal { init(validated value: Int) { "
          + "self.init(__unchecked: value) } }",
        path: "Sources/Unchecked Consumer/ExtensionInitializer.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // §A brand-owner recognizer: `Brand(__unchecked:)` is the canonical
      // typed-system bottom-out for a brand owner's own domain-validated
      // construction ([CONV-001] same-package use). Retires the per-package
      // `.excluding(rules:)` stopgap ([LINT-EXCLUDE-*]).
      if Lint.Brand.owned(Lint.Brand.vocabulary, in: source) { return [] }
      let visitor = UncheckedVisitor(
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
internal let uncheckedCallSiteMessage: Swift.String =
  "[unchecked call site] [CONV-016]: `__unchecked:` at a call site is a Tier-5 "
  + "last-resort bypass of the typed system. Prefer `.retag()` (Tier 1) or `.map()` "
  + "(Tier 2) before resorting to `__unchecked:`. The [CONV-001] extension-init "
  + "bottom-out does NOT fire: a call sitting directly in an `extension` "
  + "initializer's body that constructs that extension's own type. "
  + "**Accept-as-warning** disposition (rule fires legitimately, leave the "
  + "warning): a bottom-out spelled some other way — a nominal-type-body "
  + "initializer, a private same-package factory function, or an extension init "
  + "constructing a sibling type. Whether such a site is the sanctioned "
  + "bottom-out is package-level knowledge, not syntax; the warning is the "
  + "review signal. If this site is the typed-system "
  + "bottom-out outside the recognized shape, "
  + "escalate to supervisor and apply "
  + "`// swift-linter:disable:next unchecked call site` with a "
  + "`// REASON: <citation>` continuation."

/// True when `call` is the [CONV-001] extension-init typed-system
/// bottom-out: a call sitting directly in an initializer body, where that
/// initializer is a member of an `extension`, constructing that
/// extension's own type. See the reserve in ``UncheckedVisitor``.
internal func uncheckedIsExtensionInitBottomOut(
  call: FunctionCallExprSyntax,
  at node: Syntax
) -> Swift.Bool {
  // (1) nearest function-like ancestor must be the initializer itself.
  var current: Syntax? = node.parent
  var initializer: InitializerDeclSyntax?
  while let candidate = current {
    if let found = candidate.as(InitializerDeclSyntax.self) {
      initializer = found
      break
    }
    if candidate.is(ClosureExprSyntax.self)
      || candidate.is(FunctionDeclSyntax.self)
      || candidate.is(AccessorDeclSyntax.self)
      || candidate.is(SubscriptDeclSyntax.self)
      || candidate.is(DeinitializerDeclSyntax.self)
    {
      return false
    }
    current = candidate.parent
  }
  guard let initializer else { return false }
  // (2) the initializer must be a member of an extension.
  // `InitializerDecl → MemberBlockItem → MemberBlockItemList → MemberBlock
  // → ExtensionDecl`; walked rather than index-counted so a member-block
  // shape change does not silently turn the reserve off.
  var owning: Syntax? = initializer.parent
  var extended: TypeSyntax?
  while let candidate = owning {
    if let extensionDecl = candidate.as(ExtensionDeclSyntax.self) {
      extended = extensionDecl.extendedType
      break
    }
    if candidate.is(StructDeclSyntax.self)
      || candidate.is(ClassDeclSyntax.self)
      || candidate.is(EnumDeclSyntax.self)
      || candidate.is(ActorDeclSyntax.self)
    {
      return false
    }
    owning = candidate.parent
  }
  guard let extended else { return false }
  let owner = uncheckedTypeNameTail(extended.trimmedDescription)
  // (3) the callee must name that same type.
  return uncheckedCalleeNames(owner, in: call.calledExpression)
}

/// The last dot-separated component of a written type name, with any
/// generic argument clause dropped — `Lint.Cardinal<Int>` → `Cardinal`.
internal func uncheckedTypeNameTail(_ written: Swift.String) -> Swift.String {
  let base = written.split(separator: "<", maxSplits: 1).first.map(Swift.String.init) ?? written
  return base.split(separator: ".").last.map(Swift.String.init) ?? base
}

/// True when `callee` constructs the type named `owner` — `Owner(…)`,
/// `Self(…)`, `.init(…)`, `self.init(…)`, `Self.init(…)`, or the same with
/// a generic argument clause.
internal func uncheckedCalleeNames(
  _ owner: Swift.String,
  in callee: ExprSyntax
) -> Swift.Bool {
  if let specialized = callee.as(GenericSpecializationExprSyntax.self) {
    return uncheckedCalleeNames(owner, in: specialized.expression)
  }
  if let reference = callee.as(DeclReferenceExprSyntax.self) {
    let name = reference.baseName.text
    return name == "Self" || name == owner
  }
  if let member = callee.as(MemberAccessExprSyntax.self) {
    guard member.declName.baseName.text == "init" else { return false }
    guard let base = member.base else { return true }  // `.init(…)`
    return uncheckedCalleeNames(owner, in: base)
      || base.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
  }
  return false
}

internal final class UncheckedVisitor: SyntaxVisitor {
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

  override func visit(_ node: LabeledExprSyntax) -> SyntaxVisitorContinueKind {
    guard let label = node.label, label.text == "__unchecked" else {
      return .visitChildren
    }
    // A `LabeledExprSyntax` also matches a labeled TUPLE element
    // (`let t = (__unchecked: value)`), which is not a call site. Require
    // the enclosing labeled-expr LIST to itself sit inside a
    // `FunctionCallExprSyntax` — a call's argument list — not a
    // `TupleExprSyntax`.
    guard let call = node.parent?.parent?.as(FunctionCallExprSyntax.self) else {
      return .visitChildren
    }
    // Extension-init bottom-out reserve (#38, sourced from the 2026-08-01
    // fleet sweep). [CONV-001] sanctions `__unchecked:` as the typed-system
    // bottom-out in an extension initializer's internals, and the rule's
    // own message names that shape. The narrowest stable syntactic property
    // for it is a conjunction of three things, all present at the site:
    //
    //  1. the call sits DIRECTLY in an initializer body — no intervening
    //     closure, nested function, or accessor;
    //  2. that initializer is a member of an `extension`, not of a nominal
    //     type body (a type-body init is the declaration's own machinery
    //     and is out of the reserved shape — the ruled `self.init` fixture
    //     keeps firing);
    //  3. the callee names the extension's OWN type — `Self`, `.init`,
    //     `self.init`, `Self.init`, or the extended type's own name.
    //
    // Constructing a DIFFERENT type through `__unchecked:` from inside an
    // extension init is not a bottom-out for the type being built; it is
    // an ordinary consumer bypass and still fires.
    if uncheckedIsExtensionInitBottomOut(call: call, at: Syntax(node)) {
      return .visitChildren
    }
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
        identifier: "unchecked call site",
        message: uncheckedCallSiteMessage
      )
    )
    return .visitChildren
  }
}
