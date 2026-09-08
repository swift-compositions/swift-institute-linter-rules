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

/// Returns true if `name` is the institute `Protocol` sentinel — a
/// member name reserved for the hoisted-protocol pattern per
/// [API-IMPL-009] / [PKG-NAME-001]. The sentinel can appear either
/// raw (`Protocol`) or backtick-escaped (`` `Protocol` ``); both forms
/// signal the same intent.
///
/// Citation: [RULE-EXEMPT-5] (Protocol-sentinel) in
/// the rule-exemptions skill.
///
/// Deliberate per-pack copy of the canonical contract stated on
/// `Lint.Rule.isProtocolSentinel(_:)` (`Lint.Rule.Naming.Shared.swift`).
/// Rule packs are independently consumable library products; the
/// contract is copied, never re-derived. See #17.
internal func structureIsProtocolSentinelName(_ name: Swift.String) -> Swift.Bool {
    return name == "Protocol" || name == "`Protocol`"
}

/// The SwiftSyntax visitor-family base classes whose subclasses are
/// exempt from the structure-pack rules per [RULE-EXEMPT-7]
/// (syntax-visitor-subclass). The set covers the open base classes a
/// rule-pack visitor legitimately extends:
///
/// - `SyntaxVisitor` — most common; per-syntax-kind visit hooks.
/// - `SyntaxAnyVisitor` — any-syntax visit hook (catch-all dispatch).
/// - `SyntaxRewriter` — visit + rewrite (returns replacement syntax).
///
/// Leaf-name semantics: both bare (`SyntaxVisitor`) and qualified
/// (`SwiftSyntax.SyntaxVisitor`) inheritance forms resolve to the
/// same leaf string in the inheritance clause walk.
internal let structureSyntaxVisitorFamilyNames: Swift.Set<Swift.String> = [
    "SyntaxVisitor",
    "SyntaxAnyVisitor",
    "SyntaxRewriter",
]

/// Returns true if `clause` lists any member of the SwiftSyntax
/// visitor family (`SyntaxVisitor`, `SyntaxAnyVisitor`,
/// `SyntaxRewriter`) as an inherited type. Used by
/// `Lint.Rule.Structure.MinimalTypeBody` to skip the type-body check
/// on rule-pack visitor subclasses, whose `override func visit(_:)`
/// hooks are protocol-shaped members dictated by the base class.
///
/// Citation: [RULE-EXEMPT-7] (syntax-visitor-subclass) in
/// the rule-exemptions skill.
///
/// Leaf-name lookup mirrors `namingInheritanceLeafNames` semantics —
/// both `IdentifierTypeSyntax` (bare `SyntaxVisitor`) and
/// `MemberTypeSyntax` (qualified `SwiftSyntax.SyntaxVisitor`) resolve
/// to the visitor's name.
/// Returns true if `node` is an `AccessorBlockSyntax` in its shorthand-
/// getter form (`var x: Int { 0 }`, with no explicit `get { }`).
///
/// A short-form computed-property or subscript getter parses as
/// `AccessorBlockSyntax.getter(CodeBlockItemListSyntax)` — there is no
/// `AccessorDeclSyntax` node at all. Rules that track a function-like
/// body boundary (init body, explicit accessor body, closure body,
/// deinit body, subscript body) by testing `AccessorDeclSyntax` alone
/// miss this shorthand form entirely.
///
/// Deliberate per-pack copy of `namingIsShorthandGetterAccessorBlock`
/// from `Lint.Rule.Naming.Shared.swift`. Rule packs are independently
/// consumable library products; the contract is copied, never
/// re-derived — there is no universal/institute tier boundary between
/// two targets of this package. See #17. Semantics match.
internal func structureIsShorthandGetterAccessorBlock(_ node: Syntax) -> Swift.Bool {
    guard let block = node.as(AccessorBlockSyntax.self) else { return false }
    if case .getter = block.accessors { return true }
    return false
}

/// Whether `node` is file-significant for `single type per file`'s
/// purposes: reachable from `SourceFileSyntax` without crossing a
/// nominal-type body or a function-like body, treating
/// `ExtensionDeclSyntax` and `IfConfigDeclSyntax` as TRANSPARENT.
///
/// This is the extension-transparent sibling of
/// `Lint.Syntax.Scope.isTopLevel(_:)` (`Linter`, #17):
/// that helper stops on `ExtensionDeclSyntax`, but under the
/// institute `Nest.Name` convention every type is declared via
/// `extension Parent { struct X }`, so an extension-nested type IS
/// file-significant here — this rule must not call the primitives
/// helper bare. Declared separately, named for its own intent,
/// rather than accidentally diverging from a shared helper (#28
/// defect 4).
///
/// Walks `node.parent` upward, skipping `ExtensionDeclSyntax` and
/// `IfConfigDeclSyntax` ancestors. Returns `true` on reaching
/// `SourceFileSyntax`; returns `false` on the first nominal-type
/// (`StructDeclSyntax`, `ClassDeclSyntax`, `EnumDeclSyntax`,
/// `ActorDeclSyntax`, `ProtocolDeclSyntax`) or function-like
/// (`FunctionDeclSyntax`, `InitializerDeclSyntax`,
/// `DeinitializerDeclSyntax`, `SubscriptDeclSyntax`,
/// `AccessorDeclSyntax`, `AccessorBlockSyntax`, `ClosureExprSyntax`)
/// ancestor — a type declared inside a function body, an accessor
/// body, or a closure is not file-significant, unlike the prior
/// hand-rolled `currentDepth` counter, which never bumped depth for
/// those container kinds and so treated a function-local type as a
/// second top-level type.
internal func structureIsFileSignificant(_ node: some SyntaxProtocol) -> Swift.Bool {
    var current: Syntax? = Syntax(node).parent
    while let ancestor = current {
        if ancestor.is(SourceFileSyntax.self) {
            return true
        }
        if ancestor.is(ExtensionDeclSyntax.self) || ancestor.is(IfConfigDeclSyntax.self) {
            current = ancestor.parent
            continue
        }
        if ancestor.is(StructDeclSyntax.self)
            || ancestor.is(ClassDeclSyntax.self)
            || ancestor.is(EnumDeclSyntax.self)
            || ancestor.is(ActorDeclSyntax.self)
            || ancestor.is(ProtocolDeclSyntax.self)
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
        current = ancestor.parent
    }
    return false
}

/// Builds the dotted-path spelling of `type`, stripping backticks from
/// EACH segment independently (not the whole joined path) — the
/// ecosystem's own hoisted-protocol idiom spells the sentinel member
/// with backticks (`` `Protocol` ``), and a bare
/// `Lint.Syntax.Identifier.unescaped(_:)` call on the fully-joined path
/// would only strip the outermost pair
/// (leaving e.g. ``Foo.`Protocol`` malformed) rather than un-escaping
/// the trailing segment.
///
/// The pack's de-facto shared path helper (#28 defect 7.3) — moved
/// here from `Lint.Rule.Structure.HoistedProtocolAlias.swift`, renamed
/// from `structureHoistedProtocolAliasDottedName`, so its three
/// call sites (`HoistedProtocolAlias`, `ExtensionFileNaming`,
/// `FileNameNestedPath`) share one definition instead of a de-facto
/// shared helper living inside one rule's file.
internal func structureDottedName(of type: TypeSyntax) -> Swift.String? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return Lint.Syntax.Identifier.unescaped(identifier.name.text)
    }
    if let member = type.as(MemberTypeSyntax.self) {
        guard let baseName = structureDottedName(of: member.baseType) else {
            return nil
        }
        return "\(baseName).\(Lint.Syntax.Identifier.unescaped(member.name.text))"
    }
    if let metatype = type.as(MetatypeTypeSyntax.self) {
        guard let baseName = structureDottedName(of: metatype.baseType) else {
            return nil
        }
        return "\(baseName).\(Lint.Syntax.Identifier.unescaped(metatype.metatypeSpecifier.text))"
    }
    return nil
}

internal func structureExtendsSyntaxVisitor(_ clause: InheritanceClauseSyntax?) -> Swift.Bool {
    guard let clause else { return false }
    for inherited in clause.inheritedTypes {
        let type = inherited.type
        let leaf: Swift.String?
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            leaf = identifier.name.text
        } else if let member = type.as(MemberTypeSyntax.self) {
            leaf = member.name.text
        } else {
            leaf = nil
        }
        if let leaf, structureSyntaxVisitorFamilyNames.contains(leaf) {
            return true
        }
    }
    return false
}
