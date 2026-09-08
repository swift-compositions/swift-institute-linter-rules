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

internal import Lint
internal import SwiftSyntax

/// The canonical fix for `[PLAT-ARCH-022]`: qualify the bare stdlib
/// protocol reference.
///
/// This rule is the archetype of a mechanizable one. Its finding names a
/// single token, its fix is one qualification of that token, and the
/// qualified form is the only correct one — there is no judgment left for a
/// reader to apply. Everything the rewriter must be careful about is
/// already encoded in the detector: the same four syntactic positions, the
/// same stdlib-shadow exemption, the same composition-descending walk. The
/// rewriter mirrors the visitor rather than reimplementing its predicate,
/// so the two cannot drift into disagreeing about what is a finding.
///
/// Trivia is preserved by construction: the base and dot are synthesized
/// with none of their own, and the original identifier's leading trivia
/// moves to the base while its trailing trivia stays on the name. A fix
/// that reflowed comments or indentation would make every review of a fix
/// commit a diff review rather than a spot check.
///
/// One thing the rewriter must know that the detector does not: whether the
/// bare name it is about to qualify still means the stdlib protocol. The
/// finding is about a name that READS ambiguously and is worth making
/// wherever the name appears. The fix ASSERTS which protocol was meant, and
/// it is wrong whenever the file declares its own `Error`, `Sequence`, or
/// `Collection`: `struct Boom: Error` becomes `Boom: Swift.Error`, compiles
/// clean, and `x is Error` silently flips from true to false. A `typealias
/// Error = Swift.Error & Sendable` loses its `Sendable` bound the same way.
/// Nothing downstream catches either — the rewrite type-checks.
///
/// So the fix refuses a name the file itself declares, and the finding
/// stands for a person to resolve. The scan is file-local, which is the
/// widest scope a linter reading one file has; a shadowing declaration in a
/// sibling file or re-exported from a dependency stays outside what this can
/// see, and is sized separately before any fleet application.
internal func platformSwiftQualificationFixed(
  _ source: borrowing Lint.Source.Parsed
) -> Swift.String? {
  let rewriter = PlatformSwiftQualificationRewriter(
    declared: platformSwiftQualificationDeclaredShadowNames(in: source.tree)
  )
  let rewritten = rewriter.visit(source.tree)
  guard rewriter.changed else { return nil }
  return rewritten.description
}

/// Every shadowed-protocol name this file declares under its own definition.
///
/// A name counts as declared when the file introduces ANY entity of that
/// name — a nominal type, a protocol, a typealias, an associated type, or a
/// generic parameter. Nesting is deliberately ignored: a name declared
/// inside a namespace is still reachable unqualified from within it, and
/// deciding from syntax which references resolve to which declaration is
/// exactly the name lookup a linter does not perform. Refusing the whole
/// file costs fixes and never costs correctness.
internal func platformSwiftQualificationDeclaredShadowNames(
  in tree: SourceFileSyntax
) -> Swift.Set<Swift.String> {
  let collector = PlatformSwiftQualificationShadowDeclarationCollector()
  collector.walk(tree)
  return collector.declared
}

/// Collects the shadowed-protocol names declared anywhere in a file.
private final class PlatformSwiftQualificationShadowDeclarationCollector: SyntaxVisitor {
  var declared: Swift.Set<Swift.String> = []

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  private func record(_ name: TokenSyntax) {
    guard platformSwiftQualificationShadowedProtocols.contains(name.text) else { return }
    declared.insert(name.text)
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }

  override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
    record(node.name)
    return .visitChildren
  }
}

/// Returns `type` with every bare shadowed-protocol leaf qualified, or
/// `nil` when it holds none.
///
/// Descends exactly the shapes the detector descends — optionals, implicitly
/// unwrapped optionals, attributed types, compositions, and `some`/`any`
/// constraints — and stops at anything else. A shape the detector does not
/// look inside is a shape this must not rewrite inside either.
///
/// A leaf whose name appears in `declared` is left alone: the file gives
/// that name its own meaning, and asserting the stdlib one would change the
/// program.
internal func platformSwiftQualificationQualified(
  _ type: TypeSyntax,
  declared: Swift.Set<Swift.String> = []
) -> TypeSyntax? {
  if let optional = type.as(OptionalTypeSyntax.self) {
    guard
      let inner = platformSwiftQualificationQualified(
        optional.wrappedType,
        declared: declared
      )
    else { return nil }
    return TypeSyntax(optional.with(\.wrappedType, inner))
  }
  if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
    guard let inner = platformSwiftQualificationQualified(iuo.wrappedType, declared: declared)
    else { return nil }
    return TypeSyntax(iuo.with(\.wrappedType, inner))
  }
  if let attributed = type.as(AttributedTypeSyntax.self) {
    guard
      let inner = platformSwiftQualificationQualified(attributed.baseType, declared: declared)
    else { return nil }
    return TypeSyntax(attributed.with(\.baseType, inner))
  }
  if let composition = type.as(CompositionTypeSyntax.self) {
    var elements = composition.elements
    var changed = false
    for index in elements.indices {
      guard
        let inner = platformSwiftQualificationQualified(
          elements[index].type,
          declared: declared
        )
      else { continue }
      elements[index] = elements[index].with(\.type, inner)
      changed = true
    }
    guard changed else { return nil }
    return TypeSyntax(composition.with(\.elements, elements))
  }
  if let someAny = type.as(SomeOrAnyTypeSyntax.self) {
    guard
      let inner = platformSwiftQualificationQualified(someAny.constraint, declared: declared)
    else { return nil }
    return TypeSyntax(someAny.with(\.constraint, inner))
  }
  guard let identifier = type.as(IdentifierTypeSyntax.self),
    platformSwiftQualificationShadowedProtocols.contains(identifier.name.text),
    !declared.contains(identifier.name.text)
  else {
    return nil
  }
  let base = IdentifierTypeSyntax(
    name: .identifier("Swift", leadingTrivia: identifier.leadingTrivia)
  )
  let member = MemberTypeSyntax(
    baseType: TypeSyntax(base),
    name: identifier.name.with(\.leadingTrivia, []),
    genericArgumentClause: identifier.genericArgumentClause
  )
  return TypeSyntax(member)
}

/// Applies ``platformSwiftQualificationQualified(_:)`` at exactly the four
/// positions ``PlatformSwiftQualificationVisitor`` reports on, under the
/// same `[RULE-EXEMPT-6]` stdlib-shadow exemption.
