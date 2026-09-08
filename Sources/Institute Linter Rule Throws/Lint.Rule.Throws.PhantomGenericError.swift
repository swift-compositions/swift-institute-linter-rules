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

/// Phantom-generic error types in typed throws. Citation: `[API-ERR-009]`.
///
/// An error `enum` nested in a generic type but never using that type's
/// parameter is *accidentally* generic. As a typed-throws error it yields an
/// `@error` SIL result carrying a type parameter, which trips
/// `FunctionSignatureOpts` (`SILArgument.cpp:40 !type.hasTypeParameter()`)
/// under stock `-O -enable-default-cmo` — a build-blocker on every toolchain
/// 6.2 through 6.5-dev, not a nightly-only problem (swiftlang/swift#89617).
///
/// ## Why this rule does NOT gate on typed-throws reachability
///
/// The obvious predicate — "fire only when the enum is actually used as a
/// typed-throws error" — is **not implementable here and would fail silently.**
/// `Lint.Rule.findings` receives one `Lint.Source.Parsed`: a single file. The
/// error enum and its `typealias Failure` / `throws(…)` routinely live in
/// *different* files — swift-iso-8601 splits all four of its errors out,
/// swift-rfc-9110 all five. A same-file reachability gate therefore misses
/// almost every real instance, and it would have certified swift-rfc-9110
/// clean while that package was crashing. Over-reporting gets investigated;
/// under-reporting certifies a crashing package clean.
///
/// ## Why a token match on `throws(…)` does NOT work either
///
/// In every known manifestation the error reaches the throws clause **through a
/// typealias hop** — the literal token is `Failure`, not the nested type:
///
/// ```swift
/// public typealias Failure = RFC_7519.JWT.Parse<Input>.Error
/// public func parse(_ input: inout Input) throws(Failure) -> Output
/// ```
///
/// A later maintainer "simplifying" this rule into a match on `throws(` tokens
/// would silently gut it. Do not.
///
/// ## Two detectors, because neither alone covers the known manifestations
///
/// - **Declaration site** — a non-generic `Error`/`Failure` enum with cases,
///   nested inside a generic type *visible in the same file*, whose cases never
///   use the parameter. Catches swift-rfc-7519 and swift-w3c-xml, where the
///   enum and the generic type share a file.
/// - **Use site** — a typed-throws position naming a member type whose base
///   carries generic arguments and whose leaf is `Error`/`Failure`
///   (`…Parse<Input>.Error`). Catches swift-iso-8601 and swift-rfc-9110, where
///   the enum is in its own file but the `typealias Failure` sits beside the
///   generic type.
///
/// swift-w3c-xml spells its throws clauses **bare** (`throws(Error)`, no
/// generic arguments), so the use-site detector alone misses it; swift-rfc-9110
/// declares its enums in separate files, so the declaration-site detector alone
/// misses those. Only the union covers all four. Removing either detector
/// re-opens a class this rule exists to close.
///
/// ## Scope: the idiom, not the whole crash class
///
/// This rule targets the *idiom* that produced all four known manifestations —
/// a non-generic error enum nested in a generic type. It does NOT target every
/// input that can reach the same assertion. The published reducer for
/// swiftlang/swift#89617, for instance, declares its own generic parameter at
/// module scope (`public enum MyError<T>: Swift.Error`): it reproduces the
/// crash but not the idiom, and is correctly excluded here by the
/// "no own generic parameters" conjunct. Do not "fix" the rule to catch it —
/// that is a different predicate with a different false-positive profile.
///
/// ## Chosen precision/recall trade: the `Error`/`Failure` name gate
///
/// Firing only on enums named `Error` or `Failure` is deliberate. It held for
/// all four known manifestations, and dropping it makes every nested enum in a
/// generic type a candidate — including the namespace enums that dominated an
/// early hand-rolled scan. The accepted cost is that a differently-named error
/// (`ParseFault`, `Problem`) is missed. This is a trade, not an oversight; widen
/// the set if a manifestation ever escapes it.
///
/// ## Why remediation does not silence the use-site detector
///
/// Every verified fix *preserves the nested spelling* through a typealias
/// (`typealias Error = __DomainError`), so call sites still read
/// `throws(Error)` and `Owner<Param>.Error` after remediation. Two consequences:
/// a reachability-based predicate would have fired on all four ALREADY-FIXED
/// packages while missing the broken ones, and this rule's use-site detector
/// still fires on a remediated package whose spelling was not also cleaned up.
/// That is why the use-site finding carries its own message
/// (``throwsPhantomGenericErrorUseSiteMessage``) whose remedy is "name the
/// hoisted type directly", not "hoist it". Measured residual at adoption:
/// swift-iso-8601 3, swift-w3c-xml 1 — all stale spellings, none a crash.
extension Lint.Rule {
    public static let `phantom generic error in typed throws` = Lint.Rule(
        id: "phantom generic error in typed throws",
        default: .warning,
        controls: [
            .init(
                id: "phantom generic error declaration site",
                source: "public struct Parser<Input> { "
                    + "public enum Error: Swift.Error { case invalid } }",
                path: "Sources/Throws Consumer/PhantomErrorDeclaration.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "phantom generic error use site",
                source: "public struct Parser<Input> { "
                    + "public typealias Failure = Parser<Input>.Error }",
                path: "Sources/Throws Consumer/PhantomErrorUse.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "phantom generic error substantive parameter",
                source: "public struct Parser<Input> { "
                    + "public enum Error: Swift.Error { case invalid(Input) } }",
                path: "Sources/Throws Consumer/GenericErrorDeclaration.swift",
                expectation: .clean
            ),
            .init(
                id: "phantom generic error nongeneric owner",
                source: "public struct Parser { public enum Error: Swift.Error { case invalid } }",
                path: "Sources/Throws Consumer/NongenericErrorDeclaration.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ThrowsPhantomGenericErrorVisitor(
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
internal let throwsPhantomGenericErrorMessage: Swift.String =
    "[phantom generic error in typed throws] [API-ERR-009]: error type is nested "
    + "in a generic type but never uses its parameter — an accidentally-generic "
    + "`@error` SIL result that can trip `FunctionSignatureOpts` under "
    + "`-O -enable-default-cmo` (`SILArgument.cpp:40`, swiftlang/swift#89617), "
    + "aborting release builds of this package AND of every consumer. Hoist the "
    + "enum to non-generic module scope (`__<Domain>Error`) and keep a "
    + "`public typealias Error` on the generic type so the old spelling still "
    + "resolves — behaviour-preserving, since the cases never used the parameter. "
    + "This shape is necessary but NOT sufficient for the crash (it also needs an "
    + "eliminable argument, which is invisible here): confirm with a release build "
    + "rather than assuming either way."

/// Use-site message.
///
/// Kept separate from the declaration-site message because the remedy differs.
/// A spelling like `Parser<Input>.Error` whose `Error` is ALREADY a typealias
/// onto a hoisted non-generic enum does not crash — the type is fine, only the
/// spelling is stale. Telling those authors to "hoist the enum" would prescribe
/// work they have already done, which is how a rule earns a blanket exclusion.
/// swift-iso-8601 is exactly this case, and inconsistently so: its `DateTime`
/// parser spells `typealias Failure = __DateTimeParserError` while `Duration`,
/// `Interval` and `RecurringInterval` still carry the phantom spelling.
@usableFromInline
internal let throwsPhantomGenericErrorUseSiteMessage: Swift.String =
    "[phantom generic error in typed throws] [API-ERR-009]: typed-throws position "
    + "names an error type spelled with the enclosing type's generic arguments "
    + "(`Owner<Param>.Error`). If the error enum is NOT yet hoisted, this is the "
    + "`FunctionSignatureOpts` release-build ICE shape "
    + "(`SILArgument.cpp:40`, swiftlang/swift#89617): hoist the enum to non-generic "
    + "module scope and keep a `public typealias Error` for the old spelling. If it "
    + "IS already hoisted, the type is fine and only the spelling is stale — name "
    + "the hoisted type directly (`typealias Failure = __<Domain>Error`) so the "
    + "signature no longer reads as parameterised. Either way, confirm with a "
    + "release build rather than assuming: this shape is necessary but not "
    + "sufficient for the crash."

/// Error-type leaf names this rule recognises.
private let throwsPhantomGenericErrorNames: Set<Swift.String> = ["Error", "Failure"]

/// Leaf name of a type reference, unwrapping optionals and attributes.
private func throwsPhantomLeafName(of type: TypeSyntax) -> Swift.String? {
    var current = type
    while let optional = current.as(OptionalTypeSyntax.self) { current = optional.wrappedType }
    while let attributed = current.as(AttributedTypeSyntax.self) { current = attributed.baseType }
    if let member = current.as(MemberTypeSyntax.self) { return member.name.text }
    if let identifier = current.as(IdentifierTypeSyntax.self) { return identifier.name.text }
    return nil
}

/// Generic arguments carried by a member type's base chain (`A.B<Args>.Error`).
private func throwsPhantomBaseGenericArguments(_ type: TypeSyntax) -> [Swift.String] {
    var current = type
    while let optional = current.as(OptionalTypeSyntax.self) { current = optional.wrappedType }
    while let attributed = current.as(AttributedTypeSyntax.self) { current = attributed.baseType }
    guard let member = current.as(MemberTypeSyntax.self) else { return [] }
    var base = member.baseType
    while true {
        if let identifier = base.as(IdentifierTypeSyntax.self) {
            return identifier.genericArgumentClause?.arguments.map {
                $0.argument.trimmedDescription
            }
                ?? []
        }
        if let inner = base.as(MemberTypeSyntax.self) {
            if let clause = inner.genericArgumentClause {
                return clause.arguments.map { $0.argument.trimmedDescription }
            }
            base = inner.baseType
            continue
        }
        return []
    }
}

/// True when at least one generic argument NAMES AN IN-SCOPE GENERIC PARAMETER.
///
/// A base spelled with *concrete* arguments is a fully-specialized type: no type
/// parameter reaches the `@error` SIL result, so there is nothing to trip the
/// optimizer. `W3C_XML.Parser.swift`'s
/// `public static func fragment(_:) throws(Parser<ArraySlice<Byte>>.Error)` is exactly
/// this — `ArraySlice<Byte>` is a concrete type and `Parser.Error` is already a
/// typealias onto a non-generic enum. Firing there is a false positive, and an
/// unfixable one: it is a public throws clause, so naming the hoisted
/// `__W3CXMLParserError` directly would violate [API-ERR-007]. The current
/// spelling is correct and must stay silent.
private func throwsPhantomArgumentsAreInScopeParameters(
    _ arguments: [Swift.String],
    inScope: Set<Swift.String>
) -> Swift.Bool {
    // Exact match on the whole spelling: a bare `Input` names the parameter, while
    // a qualified `ArraySlice<Byte>` is a concrete type that merely ends in the same
    // word. Matching on the leaf would silently re-admit the false positive.
    for argument in arguments where inScope.contains(argument) { return true }
    return false
}

/// Normalised dedup key for an owner spelling.
///
/// The two detectors name the same owner differently — the declaration site
/// sees `Parse` or `RFC_7519.JWT.Parse`, the use site sees
/// `RFC_7519.JWT.Parse<Input>` — so the raw spellings must be reduced to a
/// common form or one defect reports twice. Strips generic arguments, then
/// takes the leaf component.
///
/// Known, accepted limitation: two distinct generic types with the SAME leaf
/// name in one file (`A.Parse` and `B.Parse`) collapse to one finding. The file
/// still reports, so this is not a silent zero.
private func throwsPhantomDedupKey(_ owner: Swift.String) -> Swift.String {
    let withoutGenerics = owner.prefix { $0 != "<" }
    let leaf = withoutGenerics.split(separator: ".").last.map(Swift.String.init)
    return leaf ?? Swift.String(withoutGenerics)
}

/// Generic parameter names declared by a type declaration, if any.
internal func throwsPhantomGenericParameterNames(
    _ clause: GenericParameterClauseSyntax?
) -> [Swift.String] {
    guard let clause else { return [] }
    return clause.parameters.map { $0.name.text }
}

/// Whether the enum body uses `parameter` OUTSIDE any generic-argument list —
/// i.e. whether the enum is GENUINELY generic. See
/// ``ThrowsPhantomParameterUseFinder`` for why the distinction matters.
private func throwsPhantomUsesParameterSubstantively(
    _ members: MemberBlockItemListSyntax,
    parameter: Swift.String
) -> Swift.Bool {
    let finder = ThrowsPhantomParameterUseFinder(parameter: parameter)
    for member in members { finder.walk(member) }
    return finder.found
}

internal final class ThrowsPhantomGenericErrorVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    /// Enclosing-type paths already reported in this file, so the two detectors
    /// do not double-report the same defect (they fire at different locations
    /// when the enum and its `typealias Failure` share a file).
    private var reported: Set<Swift.String> = []
    private var fileGenerics: [Swift.String: [Swift.String]] = [:]
    private var collected = false

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        if !collected {
            let collector = ThrowsPhantomGenericDeclCollector()
            collector.walk(node)
            fileGenerics = collector.generics
            collected = true
        }
        return .visitChildren
    }

    // MARK: Detector A — declaration site

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard throwsPhantomGenericErrorNames.contains(node.name.text) else { return .visitChildren }
        // An enum with its own generic parameters is genuinely generic.
        guard throwsPhantomGenericParameterNames(node.genericParameterClause).isEmpty else {
            return .visitChildren
        }
        // A caseless enum is a namespace, not an error type. Without this, every
        // `Parser<Input>.Consume`-style namespace enum fires.
        guard hasCases(node.memberBlock.members) else { return .visitChildren }

        let (owner, parameters) = enclosingGenericScope(Syntax(node))
        guard let owner, !parameters.isEmpty else { return .visitChildren }
        // Genuinely generic if any parameter is used outside generic arguments.
        for parameter in parameters
        where throwsPhantomUsesParameterSubstantively(
            node.memberBlock.members,
            parameter: parameter
        ) {
            return .visitChildren
        }
        report(
            at: node.name.positionAfterSkippingLeadingTrivia,
            owner: owner,
            message: throwsPhantomGenericErrorMessage
        )
        return .visitChildren
    }

    // MARK: Detector B — use site

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == "Failure" else { return .visitChildren }
        checkUseSite(node.initializer.value)
        return .visitChildren
    }

    override func visit(_ node: ThrowsClauseSyntax) -> SyntaxVisitorContinueKind {
        if let type = node.type { checkUseSite(type) }
        return .visitChildren
    }

    private func checkUseSite(_ type: TypeSyntax) {
        guard let leaf = throwsPhantomLeafName(of: type),
            throwsPhantomGenericErrorNames.contains(leaf)
        else { return }
        let arguments = throwsPhantomBaseGenericArguments(type)
        guard !arguments.isEmpty else { return }
        let inScope = inScopeParameters(Syntax(type))
        guard throwsPhantomArgumentsAreInScopeParameters(arguments, inScope: inScope) else {
            return
        }
        guard let member = type.as(MemberTypeSyntax.self) else { return }
        let owner = member.baseType.trimmedDescription
        report(
            at: type.positionAfterSkippingLeadingTrivia,
            owner: owner,
            message: throwsPhantomGenericErrorUseSiteMessage
        )
    }

    // MARK: Shared

    private func hasCases(_ members: MemberBlockItemListSyntax) -> Swift.Bool {
        for member in members where member.decl.is(EnumCaseDeclSyntax.self) { return true }
        return false
    }

    /// Nearest enclosing generic scope: a generic type declaration, or an
    /// extension whose extended type's leaf is a generic type declared in THIS
    /// file. Returns the owner path and its parameter names.
    private func enclosingGenericScope(_ node: Syntax) -> (Swift.String?, [Swift.String]) {
        var current = node.parent
        while let parent = current {
            if let decl = parent.as(StructDeclSyntax.self) {
                let parameters = throwsPhantomGenericParameterNames(decl.genericParameterClause)
                if !parameters.isEmpty { return (decl.name.text, parameters) }
            }
            if let decl = parent.as(EnumDeclSyntax.self) {
                let parameters = throwsPhantomGenericParameterNames(decl.genericParameterClause)
                if !parameters.isEmpty { return (decl.name.text, parameters) }
            }
            if let decl = parent.as(ClassDeclSyntax.self) {
                let parameters = throwsPhantomGenericParameterNames(decl.genericParameterClause)
                if !parameters.isEmpty { return (decl.name.text, parameters) }
            }
            if let decl = parent.as(ActorDeclSyntax.self) {
                let parameters = throwsPhantomGenericParameterNames(decl.genericParameterClause)
                if !parameters.isEmpty { return (decl.name.text, parameters) }
            }
            if let ext = parent.as(ExtensionDeclSyntax.self) {
                let path = ext.extendedType.trimmedDescription
                let leaf = path.split(separator: ".").last.map(Swift.String.init) ?? path
                if let parameters = fileGenerics[leaf], !parameters.isEmpty {
                    return (path, parameters)
                }
            }
            current = parent.parent
        }
        return (nil, [])
    }

    /// Every generic parameter name in scope at `node` — from enclosing generic
    /// type declarations, generic functions, and extensions of generic types
    /// declared in this file.
    private func inScopeParameters(_ node: Syntax) -> Set<Swift.String> {
        var names: Set<Swift.String> = []
        var current = node.parent
        while let parent = current {
            if let decl = parent.as(StructDeclSyntax.self) {
                names.formUnion(throwsPhantomGenericParameterNames(decl.genericParameterClause))
            }
            if let decl = parent.as(EnumDeclSyntax.self) {
                names.formUnion(throwsPhantomGenericParameterNames(decl.genericParameterClause))
            }
            if let decl = parent.as(ClassDeclSyntax.self) {
                names.formUnion(throwsPhantomGenericParameterNames(decl.genericParameterClause))
            }
            if let decl = parent.as(ActorDeclSyntax.self) {
                names.formUnion(throwsPhantomGenericParameterNames(decl.genericParameterClause))
            }
            if let decl = parent.as(FunctionDeclSyntax.self) {
                names.formUnion(throwsPhantomGenericParameterNames(decl.genericParameterClause))
            }
            if let ext = parent.as(ExtensionDeclSyntax.self) {
                let path = ext.extendedType.trimmedDescription
                let leaf = path.split(separator: ".").last.map(Swift.String.init) ?? path
                if let parameters = fileGenerics[leaf] { names.formUnion(parameters) }
            }
            current = parent.parent
        }
        return names
    }

    private func report(
        at position: AbsolutePosition,
        owner: Swift.String,
        message: Swift.String
    ) {
        guard reported.insert(throwsPhantomDedupKey(owner)).inserted else { return }
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
                identifier: "phantom generic error in typed throws",
                message: message
            )
        )
    }
}
