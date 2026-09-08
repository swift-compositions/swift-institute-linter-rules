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

/// Public generic APIs throwing a generic-parameter-typed error should
/// consider a non-throwing specialization. Citation: `[IMPL-042]`.
///
/// The rule fires as a REVIEW PROMPT, not a hard violation. Per
/// `[IMPL-042]`'s "When to apply" criteria the duplication is justified
/// only when the callback is invoked in a tight loop / per-token,
/// benchmarks attribute measurable cost, AND the body is stable enough
/// for duplication — if any of those conditions fails the duplication
/// is principled-absent.
///
/// The recognizer skips two well-defined cases where the rule's CODEGEN
/// premise ("the generic outer type hides the binding from codegen")
/// does not hold:
///
/// 1. `@inlinable` / `@_alwaysEmitIntoClient` declarations — the
///    developer has opted into cross-module inlining; the compiler can
///    specialize at call sites without a duplicated body.
/// 2. In-extension Never-companion already present — the recommendation
///    has been addressed; firing again is a recognizer defect, not a
///    review prompt.
extension Lint.Rule {
    public static let `generic throws missing never` = Lint.Rule(
        id: "generic throws missing never",
        default: .warning,
        controls: [
            .init(
                id: "generic throws missing never public generic failure",
                source: "public struct Parser<Sink> { "
                    + "public func parse() throws(Sink.Failure) {} }",
                path: "Sources/Throws Consumer/GenericFailure.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "generic throws missing never concrete failure",
                source: "public struct Parser<Sink> { "
                    + "public func parse() throws(Parse.Error) {} }",
                path: "Sources/Throws Consumer/ConcreteFailure.swift",
                expectation: .clean
            ),
            .init(
                id: "generic throws missing never inlinable boundary",
                source: "public struct Parser<Sink> { "
                    + "@inlinable public func parse() throws(Sink.Failure) {} }",
                path: "Sources/Throws Consumer/InlinableGenericFailure.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ThrowsGenericNeverSpecializationVisitor(
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
internal let throwsGenericNeverSpecializationMessage: Swift.String =
    "[generic throws missing never] [IMPL-042]: public "
    + "generic API throws a generic-parameter-typed error. The rule fires "
    + "as a REVIEW PROMPT — per [IMPL-042]'s 'When to apply' criteria the "
    + "duplication is justified only when the callback is invoked in a "
    + "tight loop / per-token, benchmarks attribute measurable cost, and "
    + "the body is stable for duplication. Dispositions: (a) add a non-"
    + "throwing `where <G>.<Sub> == Never` companion with a duplicated body "
    + "in the same extension — the recognizer detects in-extension "
    + "companions and won't re-fire; or (b) per-line suppress with "
    + "`// REASON:` if the 'When to apply' criteria don't hold. The rule "
    + "does not fire on `@inlinable` / `@_alwaysEmitIntoClient` "
    + "declarations because the compiler can specialize at consumer call "
    + "sites without a duplicated body."

private func gnsIsPublicOrOpen(_ modifiers: DeclModifierListSyntax) -> Swift.Bool {
    for modifier in modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public), .keyword(.open): return true
        default: continue
        }
    }
    return false
}

/// Effective-visibility variant of `gnsIsPublicOrOpen`: also true when
/// `node` declares no access modifier of its own but is a member of a
/// `public`/`open extension` — a member of a `public extension` is
/// public API in Swift without carrying the keyword, and this rule is
/// explicitly scoped to public API.
private func gnsIsPublicOrOpenEffective(
    _ node: Syntax,
    modifiers: DeclModifierListSyntax
) -> Swift.Bool {
    if gnsIsPublicOrOpen(modifiers) {
        return true
    }
    var current: Syntax? = node.parent
    while let candidate = current {
        if let ext = candidate.as(ExtensionDeclSyntax.self) {
            return gnsIsPublicOrOpen(ext.modifiers)
        }
        current = candidate.parent
    }
    return false
}

private func gnsCollectGenericParamNames(
    _ clause: GenericParameterClauseSyntax?
)
    -> Swift.Set<Swift.String>
{
    guard let clause else { return [] }
    var names: Swift.Set<Swift.String> = []
    for parameter in clause.parameters { names.insert(parameter.name.text) }
    return names
}

private func gnsGenericFailureTypePosition(
    in clause: ThrowsClauseSyntax?,
    availableGenerics: Swift.Set<Swift.String>
) -> AbsolutePosition? {
    guard let clause, let type = clause.type else { return nil }
    guard let member = type.as(MemberTypeSyntax.self) else { return nil }
    guard let base = member.baseType.as(IdentifierTypeSyntax.self) else { return nil }
    guard availableGenerics.contains(base.name.text) else { return nil }
    return member.positionAfterSkippingLeadingTrivia
}

/// Deliberately returns an empty set — a `extension Parser<Sink> { }`
/// header's generic-ARGUMENT clause cannot be told apart, from syntax
/// alone, between two semantically opposite cases: (a) `Sink` reopens
/// `Parser`'s own generic parameter of the same name (the extension
/// stays fully generic — Swift's "parameterized extension" sugar), or
/// (b) `Sink` names an unrelated CONCRETE type already in scope (the
/// extension is fully specialized — no type parameter reaches
/// codegen, e.g. `extension Parser<Data> { … throws(Data.Failure) }`
/// where `Data` is a concrete type). Only whole-program semantic
/// resolution (is there a declaration named `Sink` in scope, and is
/// IT the same `Sink` as `Parser`'s own parameter?) can distinguish
/// them; a single-file AST rule cannot.
///
/// Given that ambiguity, this rule treats every extension generic
/// argument as UNKNOWN rather than guessing "generic" — the same
/// principle `Lint.Rule.Throws.PhantomGenericError` documents at
/// length: firing on a concrete argument is a false positive, and an
/// unfixable one (the site cannot rewrite its way to silence). Erring
/// toward not firing accepts a missed review-prompt in the reopened-
/// generic case in exchange for eliminating the concrete-argument
/// false positive.
private func gnsCollectExtendedGenericNames(_ type: TypeSyntax) -> Swift.Set<Swift.String> {
    _ = type
    return []
}

/// Refinement A. `@inlinable` and `@_alwaysEmitIntoClient` opt the
/// declaration into cross-module inlining; the compiler can specialize
/// at consumer call sites without a duplicated body, so the rule's
/// codegen-scaffolding premise does not apply.
private func gnsIsInlinable(_ attributes: AttributeListSyntax) -> Swift.Bool {
    for element in attributes {
        guard let attr = element.as(AttributeSyntax.self) else { continue }
        guard let ident = attr.attributeName.as(IdentifierTypeSyntax.self) else { continue }
        switch ident.name.text {
        case "inlinable", "_alwaysEmitIntoClient": return true
        default: continue
        }
    }
    return false
}

/// Refinement B. Pre-scan the extension's members for functions /
/// initializers whose generic-where clause contains a `... == Never`
/// requirement. Their baseNames are the in-extension "companion-present"
/// set — the rule does not fire on a throwing declaration whose baseName
/// is in this set.
private func gnsCollectNeverCompanionNames(
    in extensionDecl: ExtensionDeclSyntax
) -> Swift.Set<Swift.String> {
    var names: Swift.Set<Swift.String> = []
    for memberItem in extensionDecl.memberBlock.members {
        if let funcDecl = memberItem.decl.as(FunctionDeclSyntax.self),
            gnsHasNeverFailureWhereClause(funcDecl.genericWhereClause)
        {
            names.insert(funcDecl.name.text)
        }
        if let initDecl = memberItem.decl.as(InitializerDeclSyntax.self),
            gnsHasNeverFailureWhereClause(initDecl.genericWhereClause)
        {
            names.insert("init")
        }
    }
    return names
}

/// Heuristic: any same-type requirement with `Never` on either side
/// counts as a Never companion. We don't precisely verify the LHS is
/// `<G>.<Sub>` because the companion baseName match (per
/// `gnsCollectNeverCompanionNames`) is empirically sufficient — a
/// sibling with the same baseName carrying `... == Never` is the
/// in-extension specialization the rule's recommendation calls for.
///
/// Implementation note: uses `.trimmedDescription` per the ecosystem
/// pattern in `Lint.Rule.RawValue.TaggedExtensionPublicInit` — avoids
/// the `SameTypeRequirementSyntax.LeftType` vs `TypeSyntax` typed-
/// subtype conversion needed in newer SwiftSyntax versions.
private func gnsHasNeverFailureWhereClause(_ clause: GenericWhereClauseSyntax?) -> Swift.Bool {
    guard let clause else { return false }
    for requirement in clause.requirements {
        guard let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) else {
            continue
        }
        let left = sameType.leftType.trimmedDescription
        let right = sameType.rightType.trimmedDescription
        if left == "Never" || left == "Swift.Never" { return true }
        if right == "Never" || right == "Swift.Never" { return true }
    }
    return false
}

internal final class ThrowsGenericNeverSpecializationVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    var genericsStack: [Swift.Set<Swift.String>] = []
    /// Per-extension companion-present baseNames. Companions are
    /// detected at extension-enter time via a single pre-scan of
    /// memberBlock; the stack accumulates the union across enclosing
    /// extensions for nested-extension cases.
    var companionsStack: [Swift.Set<Swift.String>] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func emit(at position: AbsolutePosition) {
        let location = converter.location(for: position)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "generic throws missing never",
                message: throwsGenericNeverSpecializationMessage
            )
        )
    }

    private func currentAvailable(
        _ funcGenerics: Swift.Set<Swift.String>
    ) -> Swift.Set<Swift.String> {
        var result: Swift.Set<Swift.String> = funcGenerics
        for set in genericsStack { result.formUnion(set) }
        return result
    }

    private func hasCompanion(_ baseName: Swift.String) -> Swift.Bool {
        for set in companionsStack {
            if set.contains(baseName) { return true }
        }
        return false
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        genericsStack.append(gnsCollectGenericParamNames(node.genericParameterClause))
        return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) { genericsStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        genericsStack.append(gnsCollectGenericParamNames(node.genericParameterClause))
        return .visitChildren
    }
    override func visitPost(_: ClassDeclSyntax) { genericsStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        genericsStack.append(gnsCollectGenericParamNames(node.genericParameterClause))
        return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) { genericsStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        genericsStack.append(gnsCollectGenericParamNames(node.genericParameterClause))
        return .visitChildren
    }
    override func visitPost(_: ActorDeclSyntax) { genericsStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        genericsStack.append(gnsCollectExtendedGenericNames(node.extendedType))
        companionsStack.append(gnsCollectNeverCompanionNames(in: node))
        return .visitChildren
    }
    override func visitPost(_: ExtensionDeclSyntax) {
        genericsStack.removeLast()
        companionsStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard gnsIsPublicOrOpenEffective(Syntax(node), modifiers: node.modifiers) else {
            return .visitChildren
        }
        // Refinement A: skip @inlinable / @_alwaysEmitIntoClient.
        if gnsIsInlinable(node.attributes) { return .visitChildren }
        // Refinement B: skip if an in-extension Never companion exists
        // with the same baseName.
        if hasCompanion(node.name.text) { return .visitChildren }
        let funcGenerics = gnsCollectGenericParamNames(node.genericParameterClause)
        let available = currentAvailable(funcGenerics)
        if let position = gnsGenericFailureTypePosition(
            in: node.signature.effectSpecifiers?.throwsClause,
            availableGenerics: available
        ) {
            emit(at: position)
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard gnsIsPublicOrOpenEffective(Syntax(node), modifiers: node.modifiers) else {
            return .visitChildren
        }
        if gnsIsInlinable(node.attributes) { return .visitChildren }
        if hasCompanion("init") { return .visitChildren }
        let funcGenerics = gnsCollectGenericParamNames(node.genericParameterClause)
        let available = currentAvailable(funcGenerics)
        if let position = gnsGenericFailureTypePosition(
            in: node.signature.effectSpecifiers?.throwsClause,
            availableGenerics: available
        ) {
            emit(at: position)
        }
        return .visitChildren
    }
}
