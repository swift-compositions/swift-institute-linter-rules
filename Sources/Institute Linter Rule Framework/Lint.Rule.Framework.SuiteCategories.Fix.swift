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

/// The canonical fix for `[TEST-005]`: append the missing canonical
/// category suites — empty `@Suite struct` declarations, in canonical
/// order — to a flagged suite's member block.
///
/// ## Hard preconditions (each an outright refusal, no partial application)
///
/// - **Refuse when the member block holds any `#if` conditional-compilation
///   block.** ``Lint.Rule.Framework.SuiteCategories``'s own predicate does
///   NOT splice `#if` when counting declared categories
///   ([#47](https://github.com/swift-compositions/swift-institute-linter-rules/issues/47)),
///   so a category satisfying the missing set may already exist inside a
///   conditional arm this fix cannot see. Inserting one unconditionally in
///   that case is a redeclaration error in whichever arm the `#if` is
///   active. This fix does not attempt to reason about which arm, or
///   splice one itself — it refuses outright wherever an `#if` collision
///   is POSSIBLE, matching the standing scope of #47 rather than
///   second-guessing it.
/// - **Refuse when any existing member — of ANY declaration kind, not only
///   `@Suite struct` — declares a name colliding with a missing category
///   name.** The rule's own predicate
///   (``suiteCategoriesMissingFromBody(_:)``) counts only `@Suite struct`
///   members as declaring a category, so a nested `enum Unit` (or a
///   stored property, function, or any other declaration merely NAMED
///   `Unit`) leaves the rule firing while an unconditional insertion of
///   `@Suite struct Unit {}` would be a redeclaration error the predicate
///   never anticipated.
/// - **Refuse when the suite holds a direct `@Test` member.** Inserting
///   empty categories there would silence the finding while leaving the
///   suite's own tests uncategorised — manufacturing compliance against
///   the convention rather than scaffolding it. Cheaply decidable from the
///   same member walk that finds collisions.
///
/// A refused-but-safe suite stays a finding — a person reading one line. A
/// fixed-but-broken (or fixed-but-hollow) file is worse than not fixing it
/// at all. Per the package's established rewriter discipline, the
/// asymmetry is the whole argument.
internal func frameworkSuiteCategoriesFixed(
    _ source: borrowing Lint.Source.Parsed
) -> Swift.String? {
    let rewriter = FrameworkSuiteCategoriesRewriter()
    let rewritten = rewriter.visit(source.tree)
    guard rewriter.changed else { return nil }
    return rewritten.description
}

/// Whether `memberBlock` may safely receive the missing category structs
/// named in `missingBareNames` (bare, unbacktick-wrapped spellings — e.g.
/// `"Edge Case"`, not `` "`Edge Case`" ``). See the type-level doc comment
/// above for why each of the three refusal cases is load-bearing.
internal func frameworkSuiteCategoriesIsFixEligible(
    _ memberBlock: MemberBlockSyntax,
    missingBareNames: [Swift.String]
) -> Swift.Bool {
    let missing = Swift.Set(missingBareNames)
    for member in memberBlock.members {
        let decl = member.decl
        if decl.is(IfConfigDeclSyntax.self) {
            return false
        }
        if let functionDecl = decl.as(FunctionDeclSyntax.self),
            frameworkSuiteCategoriesHasTestAttribute(functionDecl.attributes)
        {
            return false
        }
        for name in frameworkSuiteCategoriesDeclaredNames(decl) where missing.contains(name) {
            return false
        }
    }
    return true
}

/// Returns true if `attributes` contains `@Test` in any form (bare or
/// qualified `Testing.Test`, matching the `.Test`-suffix convention this
/// package's other predicates use for the sibling `@Suite`/`@Testing.Suite`
/// pair).
private func frameworkSuiteCategoriesHasTestAttribute(
    _ attributes: AttributeListSyntax
) -> Swift.Bool {
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        let name = attr.attributeName.trimmedDescription
        if name == "Test" || name.hasSuffix(".Test") {
            return true
        }
    }
    return false
}

/// The declared name(s) of `decl`, normalized via
/// `Lint.Syntax.Identifier.unescaped` so a backticked spelling (`` `Unit` ``)
/// compares equal to its plain form. Spans every declaration kind that
/// introduces a name into the enclosing member block's namespace — nominal
/// types, `typealias`, functions, stored/computed properties (one name per
/// binding), and enum cases (one name per element) — because the rule's own
/// predicate counts only `@Suite struct` members, and a collision with any
/// OTHER kind's name is exactly the gap this fix must not walk into. A
/// declaration kind with no name of its own (initializer, deinitializer,
/// subscript) returns empty.
private func frameworkSuiteCategoriesDeclaredNames(_ decl: DeclSyntax) -> [Swift.String] {
    if let d = decl.as(StructDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(ClassDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(EnumDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(ActorDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(ProtocolDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(TypeAliasDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(FunctionDeclSyntax.self) {
        return [Lint.Syntax.Identifier.unescaped(d.name.text)]
    }
    if let d = decl.as(VariableDeclSyntax.self) {
        return d.bindings.compactMap { binding in
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
            return Lint.Syntax.Identifier.unescaped(pattern.identifier.text)
        }
    }
    if let d = decl.as(EnumCaseDeclSyntax.self) {
        return d.elements.map { Lint.Syntax.Identifier.unescaped($0.name.text) }
    }
    return []
}

/// Strips a backtick-escaped name down to its bare spelling (`` `Edge Case`
/// `` -> `"Edge Case"`); returns `name` unchanged when it isn't backticked.
private func frameworkSuiteCategoriesBareName(_ name: Swift.String) -> Swift.String {
    guard name.hasPrefix("`"), name.hasSuffix("`"), name.count >= 2 else { return name }
    return Swift.String(name.dropFirst().dropLast())
}

/// Builds the `@Suite struct <Name> {}` member this fix appends for one
/// missing category, indented one level (4 spaces) under the flagged
/// suite's own member block. `bareName` is re-backticked here (never
/// carried pre-escaped) when it contains a space, so the raw-identifier
/// spelling stays a single, obvious point of truth.
private func frameworkSuiteCategoriesInsertedStruct(
    _ bareName: Swift.String
) -> MemberBlockItemSyntax {
    let nameText = bareName.contains(" ") ? "`\(bareName)`" : bareName
    let decl = StructDeclSyntax(
        leadingTrivia: .newline + .spaces(4),
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(
                    attributeName: IdentifierTypeSyntax(name: .identifier("Suite")),
                    trailingTrivia: .space
                )
            )
        ]),
        structKeyword: .keyword(.struct, trailingTrivia: .space),
        name: .identifier(nameText, trailingTrivia: .space),
        memberBlock: MemberBlockSyntax(
            leftBrace: .leftBraceToken(),
            members: MemberBlockItemListSyntax([]),
            rightBrace: .rightBraceToken()
        )
    )
    return MemberBlockItemSyntax(decl: DeclSyntax(decl))
}

/// Appends every missing category — in `suiteCategoriesMissingFromBody`'s
/// canonical order — to a `@Suite struct` flagged by
/// ``Lint.Rule.Framework.SuiteCategories``, or leaves the declaration
/// untouched where ``frameworkSuiteCategoriesIsFixEligible(_:missingBareNames:)``
/// refuses.
internal final class FrameworkSuiteCategoriesRewriter: SyntaxRewriter {
    var changed: Swift.Bool = false

    override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        guard suiteCategoriesHasSuiteAttribute(node.attributes) else { return super.visit(node) }
        guard suiteCategoriesIsTopLevel(Syntax(node)) else { return super.visit(node) }
        let missing = suiteCategoriesMissingFromBody(node.memberBlock)
        guard !missing.isEmpty else { return super.visit(node) }
        let missingBareNames = missing.map(frameworkSuiteCategoriesBareName)
        guard
            frameworkSuiteCategoriesIsFixEligible(
                node.memberBlock,
                missingBareNames: missingBareNames
            )
        else {
            return super.visit(node)
        }
        changed = true
        let existing = Swift.Array(node.memberBlock.members)
        let inserted = missingBareNames.map(frameworkSuiteCategoriesInsertedStruct)
        let newBlock = node.memberBlock.with(
            \.members,
            MemberBlockItemListSyntax(existing + inserted)
        )
        return super.visit(node.with(\.memberBlock, newBlock))
    }
}
