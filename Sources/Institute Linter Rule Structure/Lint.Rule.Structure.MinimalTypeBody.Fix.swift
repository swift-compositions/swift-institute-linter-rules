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

/// The canonical fix for `[API-IMPL-008]`: move the members the rule flags
/// out of the primary type body into a same-file `extension`.
///
/// ## Hard preconditions (each an outright refusal, no partial application)
///
/// - **`class` and `actor` declarations are never touched.** A method in a
///   class body is dynamically dispatched and overridable; the same method
///   in an extension is not. Where nothing overrides it the rewrite
///   silently changes dispatch semantics; where something does, it breaks
///   the build. Only `visit(_:StructDeclSyntax)` and
///   `visit(_:EnumDeclSyntax)` are overridden below — a `class` or `actor`
///   body is never rewritten, at any nesting depth, and its members are
///   never partially moved.
/// - **The generated extension is always emitted at file scope**, because
///   that is the only place Swift allows an `extension` declaration at all
///   (verified: `extension` nested inside another type or extension body is
///   `error: declaration is only valid at file scope`). Same-file placement
///   is therefore not a style choice this fix could relax — it is what
///   keeps `private` members of the moved-from type mutually visible to the
///   moved-out members (Swift extends `private` to same-file extensions of
///   the declaring type), and it is preserved by construction here, not by
///   a check that could drift from the engine's own same-file fix contract.
///
/// ## Scope this fix accepts, and why narrower is safe
///
/// Only a struct/enum reachable from `SourceFileSyntax` by climbing
/// EXCLUSIVELY `ExtensionDeclSyntax` ancestors is fixed —
/// ``structureMinimalTypeBodyIsFixEligible(_:)``. A struct/enum nested
/// inside another nominal type (including inside a `class`/`actor` body) is
/// left as a standing, unfixed finding. This is deliberately narrower than
/// the detector, which fires at any nesting depth:
///
/// - The fix's only tool for referencing a nested type from file scope is
///   `Outer.Inner`, built by reusing the enclosing `extension`'s own
///   `extendedType` syntax (never a re-parsed string) via
///   ``structureMinimalTypeBodyEnclosingExtendedType(_:)``. That composes
///   safely through the institute's own `extension Parent { struct X }`
///   idiom (at most one `ExtensionDeclSyntax` ancestor, since an extension
///   itself is never nested — see the file-scope rule above), but does not
///   generalize soundly through an arbitrary chain of nominal-type
///   ancestors without risking a name collision or losing a generic
///   parameter list this syntax-only rewriter cannot see resolved.
/// - A struct/enum declared inside `#if` is ALSO excluded, even though it
///   IS reachable through extension-only ancestors otherwise. Unlike
///   `structureIsFileSignificant` (`Lint.Rule.Structure.Shared.swift`),
///   `#if` is NOT transparent here: the generated extension is emitted
///   unconditionally, so fixing a declaration that exists only under a
///   platform condition would reference a type absent on every other
///   platform the output must still compile on.
/// - A struct/enum carrying `@available` — on the declaration itself, OR
///   inherited from an enclosing `extension` on the climb this fix already
///   performs — is ALSO excluded. The generated extension carries no
///   attribute list, so `extension Widget { … }` for a `@available(macOS
///   15, *) struct Widget` fails to compile: `'Widget' is only available
///   in macOS 15 or newer`. The enclosing-extension case is not
///   incidental — it is the repository's own house idiom (`extension
///   Lint.Rule { @available(...) ... struct \`X Tests\` { ... } }`), and a
///   predicate that inspected only the declaration's own attributes would
///   miss it entirely. Copying the attribute list into the generated
///   extension is not attempted: it is not safe in general (an
///   `@available` platform/version pair does not always transfer
///   correctly onto a same-file `extension` of the same type — see the
///   package's `class`/`actor` refusal above for the same asymmetry
///   argument), so this fix refuses rather than propagates.
///
/// A refused-but-safe declaration stays a finding — a person reading one
/// line. A fixed-but-broken file is a silent behaviour change nobody
/// reviewed. Per the package's established rewriter discipline, the
/// asymmetry is the whole argument.
///
/// ## Members this fix moves, and the one category it declines
///
/// ``structureMinimalTypeBodyPartition(_:)`` moves exactly what
/// `StructureMinimalTypeBodyVisitor.checkMembers(_:)` flags: static/class
/// properties, computed properties, functions, subscripts, non-sentinel
/// typealiases, nested types without the extension-pattern attribute, and
/// nested protocols. It declines one thing the detector still flags: a
/// member wrapped in `#if`. `Lint.Syntax.Conditional.members(_:)` splices `#if`
/// clauses so the DETECTOR still sees what is inside them, but moving only
/// the inner declaration out from under its `#if` guard would silently drop
/// the conditional-compilation boundary. A mechanical fix must not do that,
/// so an `#if`-guarded member is left in the primary body — unmoved,
/// unconditionally correct, and (if flagged) still a standing finding for a
/// person to resolve.
internal func structureMinimalTypeBodyFixed(
  _ source: borrowing Lint.Source.Parsed
) -> Swift.String? {
  let rewriter = StructureMinimalTypeBodyRewriter()
  let rewritten = rewriter.visit(source.tree)
  guard rewriter.changed else { return nil }
  var statements = rewritten.statements
  for extensionDecl in rewriter.pendingExtensions {
    statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(extensionDecl))))
  }
  return rewritten.with(\.statements, statements).description
}

/// Whether `node` sits where this fix may safely act: reachable from
/// `SourceFileSyntax` by climbing only `ExtensionDeclSyntax` ancestors, with
/// no intervening nominal-type ancestor and no intervening `#if`
/// conditional-compilation block. See the type-level doc comment above for
/// why both restrictions are load-bearing, not merely conservative.
internal func structureMinimalTypeBodyIsFixEligible(_ node: Syntax) -> Swift.Bool {
  var current = node.parent
  while let ancestor = current {
    if ancestor.is(SourceFileSyntax.self) {
      return true
    }
    if let ext = ancestor.as(ExtensionDeclSyntax.self) {
      // An `@available` on an enclosing extension is inherited by every
      // member declared inside it, including a nested struct/enum with no
      // attribute of its own. The generated extension carries no
      // attribute list, so this must refuse exactly like a directly
      // attributed declaration does (checked separately, on the
      // declaration's own attributes, by the caller).
      if structureMinimalTypeBodyHasAvailableAttribute(ext.attributes) {
        return false
      }
      current = ancestor.parent
      continue
    }
    // Any nominal-type body, `#if` block, or function-like body between
    // `node` and `SourceFileSyntax` disqualifies — climbing PAST a
    // non-extension, non-list/item wrapper node here would mean the fix
    // guessed at a position it cannot express as a top-level `extension`.
    if ancestor.is(StructDeclSyntax.self)
      || ancestor.is(ClassDeclSyntax.self)
      || ancestor.is(EnumDeclSyntax.self)
      || ancestor.is(ActorDeclSyntax.self)
      || ancestor.is(ProtocolDeclSyntax.self)
      || ancestor.is(IfConfigDeclSyntax.self)
      || ancestor.is(FunctionDeclSyntax.self)
      || ancestor.is(InitializerDeclSyntax.self)
      || ancestor.is(DeinitializerDeclSyntax.self)
      || ancestor.is(SubscriptDeclSyntax.self)
      || ancestor.is(AccessorDeclSyntax.self)
      || ancestor.is(AccessorBlockSyntax.self)
      || ancestor.is(ClosureExprSyntax.self)
    {
      return false
    }
    // Anything else (a list/item wrapper node such as
    // `CodeBlockItemSyntax`/`CodeBlockItemListSyntax` at file scope, or
    // `MemberBlockItemSyntax`/`MemberBlockSyntax` inside an extension) is
    // transparent — keep climbing.
    current = ancestor.parent
  }
  return false
}

/// Returns true if `attributes` contains `@available` in any form
/// (`@available(macOS 15, *)`, `@available(*, deprecated)`, and so on — any
/// argument list). Shared by ``structureMinimalTypeBodyIsFixEligible(_:)``
/// (checking every climbed `extension` ancestor) and the rewriter's own
/// `fixed(node:name:block:)` (checking the declaration's own attributes):
/// an extension's `@available` is inherited by its members, but a nested
/// declaration's own `@available` must refuse independently of its
/// ancestors too.
internal func structureMinimalTypeBodyHasAvailableAttribute(
  _ attributes: AttributeListSyntax
) -> Swift.Bool {
  for attribute in attributes {
    guard let attr = attribute.as(AttributeSyntax.self) else { continue }
    if attr.attributeName.trimmedDescription == "available" {
      return true
    }
  }
  return false
}

/// The nearest enclosing `extension`'s own extended-type syntax, or `nil`
/// when `node` is declared directly at file scope.
///
/// Reuses the ORIGINAL syntax node — never a re-parsed string — so a
/// backticked raw-identifier segment, a generic-argument clause, and every
/// other detail of the extension's own spelling carries over exactly into
/// the generated extension's `Outer.Inner` reference. Safe to call only
/// after ``structureMinimalTypeBodyIsFixEligible(_:)`` has confirmed the
/// ancestor chain holds at most one `ExtensionDeclSyntax` (extensions are
/// never themselves nested — see the type-level doc comment above).
internal func structureMinimalTypeBodyEnclosingExtendedType(_ node: Syntax) -> TypeSyntax? {
  var current = node.parent
  while let ancestor = current {
    if let ext = ancestor.as(ExtensionDeclSyntax.self) {
      return ext.extendedType
    }
    if ancestor.is(SourceFileSyntax.self) { return nil }
    current = ancestor.parent
  }
  return nil
}

/// Builds the `Outer.Inner` (or bare `Inner`) type reference the generated
/// extension's `extendedType` uses, from the fixable declaration's own name
/// token and its (possibly absent) enclosing extension.
internal func structureMinimalTypeBodyExtendedType(
  for node: Syntax,
  ownName: TokenSyntax
) -> TypeSyntax {
  let bareName = ownName.with(\.leadingTrivia, []).with(\.trailingTrivia, [])
  guard let enclosing = structureMinimalTypeBodyEnclosingExtendedType(node) else {
    return TypeSyntax(IdentifierTypeSyntax(name: bareName))
  }
  let base = enclosing.with(\.leadingTrivia, []).with(\.trailingTrivia, [])
  return TypeSyntax(MemberTypeSyntax(baseType: base, name: bareName))
}

/// Whether a nested struct/class/enum/actor MEMBER may be moved whole, as a
/// single unit, into the parent's generated extension.
///
/// A nested type without the extension-pattern attribute is always a
/// "movable member" of its PARENT's finding — the detector flags it as a
/// nested type that must move. But moving it verbatim is only safe when the
/// nested type has no movable members of ITS OWN: if it does, relocating it
/// whole would swap the parent's "nested type in body" finding for the
/// nested type's own STILL-STANDING "members in body" finding at its new
/// location — a rewrite that doesn't make the file re-lint clean, which
/// this package's rewriters never emit. Recursing into
/// ``structureMinimalTypeBodyPartition(_:)`` answers exactly that: `nil`
/// means the nested type is already minimal (or exempt) and safe to move as
/// a unit; non-`nil` means it has its own violation, so it stays put and
/// remains a standing (unfixed) finding at its original position, same as
/// a `class`/`actor` member ever would.
internal func structureMinimalTypeBodyMayMoveNestedTypeWhole(
  _ attributes: AttributeListSyntax,
  _ memberBlock: MemberBlockSyntax
) -> Swift.Bool {
  guard !structureMinimalTypeBodyHasExtensionPatternAttribute(attributes) else { return false }
  return structureMinimalTypeBodyPartition(memberBlock) == nil
}

/// Splits `block`'s members into what MUST stay in the primary body and
/// what the canonical fix moves into a same-file extension, mirroring
/// exactly the branches `StructureMinimalTypeBodyVisitor.checkMembers(_:)`
/// flags. Returns `nil` when nothing is movable.
///
/// Deliberately narrower than the detector in one respect: a member wrapped
/// in `#if` is left in `remaining` unconditionally, never partitioned into
/// `moved` — see the type-level doc comment on
/// ``structureMinimalTypeBodyFixed(_:)`` for why.
internal func structureMinimalTypeBodyPartition(
  _ block: MemberBlockSyntax
) -> (remaining: MemberBlockItemListSyntax, moved: [MemberBlockItemSyntax])? {
  var remaining: [MemberBlockItemSyntax] = []
  var moved: [MemberBlockItemSyntax] = []

  for member in block.members {
    let decl = member.decl
    if let variable = decl.as(VariableDeclSyntax.self) {
      if structureMinimalTypeBodyIsStaticOrClassMember(variable.modifiers)
        || structureMinimalTypeBodyIsComputedProperty(variable)
      {
        moved.append(member)
      } else {
        remaining.append(member)
      }
      continue
    }
    if decl.is(FunctionDeclSyntax.self) || decl.is(SubscriptDeclSyntax.self) {
      moved.append(member)
      continue
    }
    if let typealiasDecl = decl.as(TypeAliasDeclSyntax.self) {
      if structureIsProtocolSentinelName(typealiasDecl.name.text) {
        remaining.append(member)
      } else {
        moved.append(member)
      }
      continue
    }
    if let nested = decl.as(StructDeclSyntax.self) {
      if structureMinimalTypeBodyMayMoveNestedTypeWhole(nested.attributes, nested.memberBlock) {
        moved.append(member)
      } else {
        remaining.append(member)
      }
      continue
    }
    if let nested = decl.as(ClassDeclSyntax.self) {
      if structureMinimalTypeBodyMayMoveNestedTypeWhole(nested.attributes, nested.memberBlock) {
        moved.append(member)
      } else {
        remaining.append(member)
      }
      continue
    }
    if let nested = decl.as(EnumDeclSyntax.self) {
      if structureMinimalTypeBodyMayMoveNestedTypeWhole(nested.attributes, nested.memberBlock) {
        moved.append(member)
      } else {
        remaining.append(member)
      }
      continue
    }
    if let nested = decl.as(ActorDeclSyntax.self) {
      if structureMinimalTypeBodyMayMoveNestedTypeWhole(nested.attributes, nested.memberBlock) {
        moved.append(member)
      } else {
        remaining.append(member)
      }
      continue
    }
    if decl.is(ProtocolDeclSyntax.self) {
      moved.append(member)
      continue
    }
    // Stored properties, the canonical initializer(s), `deinit`, enum
    // cases, and `#if`-wrapped members (any decl kind) all stay.
    remaining.append(member)
  }

  guard !moved.isEmpty else { return nil }
  return (MemberBlockItemListSyntax(remaining), moved)
}

/// Builds the same-file extension a fixed struct/enum's moved members land
/// in.
private func structureMinimalTypeBodyExtension(
  extendedType: TypeSyntax,
  members: [MemberBlockItemSyntax]
) -> ExtensionDeclSyntax {
  ExtensionDeclSyntax(
    leadingTrivia: .newlines(2),
    extensionKeyword: .keyword(.extension, trailingTrivia: .space),
    extendedType: extendedType,
    memberBlock: MemberBlockSyntax(
      leftBrace: .leftBraceToken(leadingTrivia: .space),
      members: MemberBlockItemListSyntax(members)
    )
  )
}

/// Moves each fixable struct/enum's flagged members into a same-file
/// extension, collected via ``pendingExtensions`` and appended to the file
/// by ``structureMinimalTypeBodyFixed(_:)`` after the tree walk completes —
/// an `extension` is only ever valid at file scope, so it cannot be
/// returned from inside a nested `visit(_:StructDeclSyntax)` /
/// `visit(_:EnumDeclSyntax)` call.
///
/// `class` and `actor` declarations are never overridden here, so the
/// default `SyntaxRewriter` behaviour recurses into their members
/// unchanged — a value type nested inside a class/actor body is still out
/// of THIS fix's scope too (`structureMinimalTypeBodyIsFixEligible(_:)`
/// disqualifies on ANY nominal-type ancestor, class/actor included), but a
/// class/actor's own members are never even considered for the split.
internal final class StructureMinimalTypeBodyRewriter: SyntaxRewriter {
  var changed: Swift.Bool = false
  var pendingExtensions: [ExtensionDeclSyntax] = []

  override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
    guard let rewritten = fixed(node: node, name: node.name, block: node.memberBlock) else {
      return super.visit(node)
    }
    changed = true
    return super.visit(node.with(\.memberBlock, rewritten))
  }

  override func visit(_ node: EnumDeclSyntax) -> DeclSyntax {
    guard let rewritten = fixed(node: node, name: node.name, block: node.memberBlock) else {
      return super.visit(node)
    }
    changed = true
    return super.visit(node.with(\.memberBlock, rewritten))
  }

  /// Shared struct/enum logic: eligible position, not extension-pattern
  /// exempt, and at least one movable member. Returns the primary type's
  /// NEW member block (with moved members removed) and records the
  /// generated extension in ``pendingExtensions``, or `nil` when this
  /// declaration is not fixed.
  private func fixed(
    node: some SyntaxProtocol,
    name: TokenSyntax,
    block: MemberBlockSyntax
  ) -> MemberBlockSyntax? {
    guard structureMinimalTypeBodyIsFixEligible(Syntax(node)) else { return nil }
    guard !structureMinimalTypeBodyHasExtensionPatternAttribute(attributes(of: node)) else {
      return nil
    }
    guard !structureMinimalTypeBodyHasAvailableAttribute(attributes(of: node)) else {
      return nil
    }
    guard let (remaining, moved) = structureMinimalTypeBodyPartition(block) else { return nil }
    let extendedType = structureMinimalTypeBodyExtendedType(for: Syntax(node), ownName: name)
    pendingExtensions.append(
      structureMinimalTypeBodyExtension(extendedType: extendedType, members: moved)
    )
    return block.with(\.members, remaining)
  }

  private func attributes(of node: some SyntaxProtocol) -> AttributeListSyntax {
    if let structDecl = node.as(StructDeclSyntax.self) { return structDecl.attributes }
    if let enumDecl = node.as(EnumDeclSyntax.self) { return enumDecl.attributes }
    return AttributeListSyntax([])
  }
}
