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

/// A phantom generic parameter — a pure compile-time discriminator over
/// `Tagged` / `Index` / `Property` — MUST be bound `~Copyable & ~Escapable`,
/// not bare and not `~Copyable`-only. Citation: `[API-NAME-010b]`.
///
/// ADVISORY (non-gating, `.warning`). Conservative by design: it flags the
/// two cleanest shapes and never a stored-value parameter.
///   1. `extension Tagged where … <P>: ~Copyable { … }` (and `Index` /
///      `Property` extensions) — the extended type's first parameter is
///      definitionally phantom, so a `~Copyable`-only bound under-suppresses.
///   2. A `func` / `init` / `subscript` / `typealias` generic parameter
///      `<P: ~Copyable>` that appears as the FIRST type-argument of a
///      `Tagged<P,…>` / `Index<P>` / `Property<P,…>` in the declaration AND
///      never as a stored / by-value position (`: P`, `[P]`, `-> P`, `P?`,
///      `consuming`/`borrowing`/`inout P`) AND never bound into a
///      value-storing container through a same-type `where`-clause
///      requirement on another generic parameter (e.g. `where S ==
///      Buffer<Storage::Storage<Allocator<Resource>>.Contiguous<P>>.Linear` — `P`
///      reaches the storage type as a nested generic argument of the
///      requirement's concrete type, not through a `: P` text position).
///      Same-signature column-generic L1 shape; see [API-NAME-010b]
///      outcome record, swift-array#9 adjudication (comment
///      5134794606, 2026-07-30).
/// The bare-`<P>` form and the `extension Tagged where … Tag: ~Copyable`
/// associatedtype/conditional-conformance companions are intentionally out of
/// this conservative scope — see the outcome record.
extension Lint.Rule {
    public static let `phantom suppression` = Lint.Rule(
        id: "phantom suppression",
        default: .warning,
        controls: [
            .init(
                id: "phantom suppression copyable only",
                source: "extension Tagged where Underlying == Ordinal, Tag: ~Copyable { public var probe: Int { 0 } }",
                path: "Sources/Naming Core/CopyableOnly.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "phantom suppression maximal bound",
                source: "extension Tagged where Underlying == Ordinal, Tag: ~Copyable & ~Escapable { public var probe: Int { 0 } }",
                path: "Sources/Naming Core/MaximalBound.swift",
                expectation: .clean
            ),
            .init(
                id: "phantom suppression stored value",
                source: "extension Sequence { public func collect<Element: ~Copyable>(_ value: [Element]) {} }",
                path: "Sources/Naming Core/StoredValue.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingPhantomSuppressionVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingPhantomSuppressionMessage: Swift.String =
    "[phantom suppression] [API-NAME-010b]: phantom generic parameter (a pure "
    + "Tagged/Index/Property discriminator, never stored) is under-suppressed — "
    + "bind it `~Copyable & ~Escapable`, not `~Copyable`-only or bare. A marker "
    + "requirement on a phantom is vacuous over-constraint (Reynolds parametricity)."

internal final class NamingPhantomSuppressionVisitor: SyntaxVisitor {
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

    // Shape 1 — `extension Tagged/Index/Property where <phantom>: ~Copyable`.
    //
    // Only the wrapper's PHANTOM parameter is in scope (`Tag` for
    // `Tagged`/`Property`, `Element` for `Index` — the first parameter,
    // definitionally phantom). Other where-clause identifiers (`Underlying`,
    // `Base`, …) name STORED / value parameters, where a `~Copyable`-only
    // bound is correct — firing there was a false-positive class surfaced
    // on swift-tagged' own surface (Tagged.swift `Underlying:
    // ~Copyable` extensions, 2026-07-07 tower-validation follow-up).
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let wrapper = phantomWrapperBaseName(node.extendedType) else { return .visitChildren }
        guard let whereClause = node.genericWhereClause else { return .visitChildren }
        for requirement in whereClause.requirements {
            guard case .conformanceRequirement(let conformance) = requirement.requirement else {
                continue
            }
            guard let left = conformance.leftType.as(IdentifierTypeSyntax.self) else { continue }
            guard left.name.text == phantomParameterName(ofWrapper: wrapper) else { continue }
            if constraintIsCopyableOnly(conformance.rightType) {
                emit(at: conformance.rightType.positionAfterSkippingLeadingTrivia)
            }
        }
        return .visitChildren
    }

    // Shape 2 — generic parameter `<P: ~Copyable>` used as a Tagged/Index/Property
    // first-arg discriminator and never stored.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        checkGenericParameters(
            node.genericParameterClause,
            whereClause: node.genericWhereClause,
            in: Syntax(node)
        )
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        checkGenericParameters(
            node.genericParameterClause,
            whereClause: node.genericWhereClause,
            in: Syntax(node)
        )
        return .visitChildren
    }
    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        checkGenericParameters(
            node.genericParameterClause,
            whereClause: node.genericWhereClause,
            in: Syntax(node)
        )
        return .visitChildren
    }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        checkGenericParameters(
            node.genericParameterClause,
            whereClause: node.genericWhereClause,
            in: Syntax(node)
        )
        return .visitChildren
    }

    private func checkGenericParameters(
        _ clause: GenericParameterClauseSyntax?,
        whereClause: GenericWhereClauseSyntax?,
        in decl: Syntax
    ) {
        guard let clause else { return }
        // `trimmedDescription`, not `description` — the latter includes leading
        // trivia (the declaration's own doc comment), and the text heuristics
        // below would otherwise match prose inside a `///` comment as if it
        // were code (e.g. `/// See [Tag]` or `/// Tagged<Tag, Underlying>`).
        let body = decl.trimmedDescription
        for parameter in clause.parameters {
            let name = parameter.name.text
            // Only `<P: ~Copyable>` (bare `<P>` is out of this conservative scope —
            // its phantom-ness can't be confirmed without whole-type analysis here).
            guard let inherited = parameter.inheritedType, constraintIsCopyableOnly(inherited)
            else {
                continue
            }
            guard usedAsPhantomDiscriminator(name, in: body), !usedAsStoredValue(name, in: body),
                !usedAsWhereClauseContainerBinding(name, in: whereClause),
                !usedAtStructurallyEscapablePosition(name, in: body)
            else {
                continue
            }
            emit(at: parameter.name.positionAfterSkippingLeadingTrivia)
        }
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
                identifier: "phantom suppression",
                message: namingPhantomSuppressionMessage
            )
        )
    }
}

/// The phantom (first) generic parameter's canonical name for each
/// supported wrapper: `Tagged<Tag, Underlying>` / `Property<Tag, …>` →
/// `Tag`; `Index<Element> = Tagged<Element, Ordinal>` → `Element`.
/// Shape 1 only inspects requirements on this parameter — the wrapper's
/// remaining parameters are stored/value positions.
private func phantomParameterName(ofWrapper leaf: Swift.String) -> Swift.String {
    leaf == "Index" ? "Element" : "Tag"
}

/// The wrapper's leaf name if `type` is `Tagged` / `Index` / `Property`
/// (bare or member-qualified, e.g. `Index.Index`), else nil.
private func phantomWrapperBaseName(_ type: TypeSyntax) -> Swift.String? {
    let leaf: Swift.String?
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        leaf = identifier.name.text
    } else if let member = type.as(MemberTypeSyntax.self) {
        leaf = member.name.text
    } else {
        leaf = nil
    }
    guard let leaf, leaf == "Tagged" || leaf == "Index" || leaf == "Property" else { return nil }
    return leaf
}

/// True when `type` is `~Copyable` (a lone suppressed `Copyable`) and is NOT a
/// composition that already includes `~Escapable`.
private func constraintIsCopyableOnly(_ type: TypeSyntax) -> Swift.Bool {
    if let suppressed = type.as(SuppressedTypeSyntax.self) {
        return suppressedIsCopyable(suppressed)
    }
    if let composition = type.as(CompositionTypeSyntax.self) {
        var sawCopyable = false
        var sawEscapable = false
        for element in composition.elements {
            if let suppressed = element.type.as(SuppressedTypeSyntax.self) {
                if suppressedIsCopyable(suppressed) { sawCopyable = true }
                if suppressedLeaf(suppressed) == "Escapable" { sawEscapable = true }
            }
        }
        return sawCopyable && !sawEscapable
    }
    return false
}

private func suppressedIsCopyable(_ suppressed: SuppressedTypeSyntax) -> Swift.Bool {
    suppressedLeaf(suppressed) == "Copyable"
}

private func suppressedLeaf(_ suppressed: SuppressedTypeSyntax) -> Swift.String? {
    suppressed.type.as(IdentifierTypeSyntax.self)?.name.text
}

/// Text heuristic: `name` appears as the first type-argument of a phantom wrapper.
private func usedAsPhantomDiscriminator(_ name: Swift.String, in body: Swift.String) -> Swift.Bool {
    for wrapper in ["Tagged<", "Index<", "Property<"] {
        if body.contains(wrapper + name + ",") || body.contains(wrapper + name + ">") {
            return true
        }
    }
    return false
}

/// Text heuristic: `name` appears in a stored / by-value position. Conservative —
/// any hit suppresses the flag (we never warn on a possible stored param).
private func usedAsStoredValue(_ name: Swift.String, in body: Swift.String) -> Swift.Bool {
    for marker in [
        "[" + name + "]", "-> " + name, ": " + name + ")", ": " + name + " ",
        ": " + name + ",", ": " + name + "\n", name + "?",
        "consuming " + name, "borrowing " + name, "inout " + name,
    ] where body.contains(marker) {
        return true
    }
    return false
}

/// Stdlib generic types whose generic parameter is CONSTRAINED to be
/// `Escapable` by the stdlib's own declaration — `UnsafePointer<Pointee>`
/// and family do not carry `Pointee: ~Escapable`. A generic parameter
/// passed to one of these cannot also be declared `~Escapable`.
private let namingPhantomEscapableConstrainedGenericTypes: [Swift.String] = [
    "UnsafePointer",
    "UnsafeMutablePointer",
    "UnsafeBufferPointer",
    "UnsafeMutableBufferPointer",
    "AutoreleasingUnsafeMutablePointer",
    "ManagedBuffer",
    "ManagedBufferPointer",
]

/// True when `name` reaches a generic position whose stdlib declaration
/// already requires `Escapable` — the rule's own prescribed fix
/// (`~Copyable & ~Escapable`) then does not compile.
///
/// Phantom-suppression defect (swift-institute/.github#90 comment
/// 5150641576 item 1, sourced from the batch-1 backlog, comment
/// 5150595934, `swift-molecules/swift-ordinal` entry
/// "phantom-suppression prescribed fix doesn't compile"): a `<P: ~Copyable>`
/// used as a `Tagged<P, …>` discriminator AND as `UnsafeMutablePointer<P>`'s
/// `Pointee` is structurally `Escapable`. `Pointee` has no `~Escapable`
/// suppression in the stdlib, so `<P: ~Copyable & ~Escapable>` is rejected
/// by the compiler. A rule whose prescribed fix does not compile is a
/// defect, not a finding: such a parameter is not a pure phantom and is
/// out of scope.
///
/// Text heuristic, matching the surrounding `usedAsStoredValue` /
/// `usedAsPhantomDiscriminator` style: the parameter must appear as a
/// direct generic argument (`UnsafeMutablePointer<P>` or
/// `UnsafeMutablePointer<P, …>`) of one of the listed types. Conservative
/// by construction — any hit suppresses the flag.
private func usedAtStructurallyEscapablePosition(
    _ name: Swift.String,
    in body: Swift.String
) -> Swift.Bool {
    for type in namingPhantomEscapableConstrainedGenericTypes {
        if body.contains(type + "<" + name + ">") || body.contains(type + "<" + name + ",") {
            return true
        }
    }
    return false
}

/// True when `name` is bound into a value-storing container through a
/// same-type `where`-clause requirement on a DIFFERENT generic parameter —
/// e.g. `where S == Buffer<Storage::Storage<Memory.Allocator<Resource>>.Contiguous<E>>.Linear`
/// binds `E` as a nested generic argument of `Contiguous`, which stores
/// values of `E`. Citation: [API-NAME-010b] outcome record,
/// swift-array#9 adjudication (comment 5134794606, 2026-07-30).
///
/// This is a same-signature shape the text-based ``usedAsStoredValue(_:in:)``
/// heuristic cannot see: `name` never appears at a `: E` / `[E]` / `-> E`
/// text position — it only appears nested inside the CONCRETE TYPE bound to
/// another generic parameter (`S`) by the declaration's own `where` clause.
/// A generic parameter that only ever surfaces this way is, structurally,
/// exactly as much a stored value as one spelled `: E` directly — the
/// `where`-clause substitution is how the container's element type reaches
/// the storage type, not a phantom-discriminator position.
private func usedAsWhereClauseContainerBinding(
    _ name: Swift.String,
    in whereClause: GenericWhereClauseSyntax?
) -> Swift.Bool {
    guard let whereClause else { return false }
    for requirement in whereClause.requirements {
        guard case .sameTypeRequirement(let sameType) = requirement.requirement else { continue }
        if let leftType = sameType.leftType.as(TypeSyntax.self),
            usedAsGenericArgument(name, in: leftType)
        {
            return true
        }
        if let rightType = sameType.rightType.as(TypeSyntax.self),
            usedAsGenericArgument(name, in: rightType)
        {
            return true
        }
    }
    return false
}

/// True when `name` occurs as a nested generic type-argument anywhere
/// inside `type` — never as `type`'s own bare leaf name, only inside one
/// of its (or an ancestor member segment's) generic-argument list. Detects
/// container bindings like `Storage::Storage<Memory.Allocator<Resource>>.Contiguous<E>`,
/// where `E` is the sole generic argument of the `.Contiguous` member
/// segment, nested two levels below the requirement's top-level type.
private func usedAsGenericArgument(_ name: Swift.String, in type: TypeSyntax) -> Swift.Bool {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return genericArgumentsBind(name, identifier.genericArgumentClause)
    }
    if let member = type.as(MemberTypeSyntax.self) {
        if genericArgumentsBind(name, member.genericArgumentClause) { return true }
        return usedAsGenericArgument(name, in: member.baseType)
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return usedAsGenericArgument(name, in: optional.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return usedAsGenericArgument(name, in: attributed.baseType)
    }
    return false
}

/// True when any argument of `clause` either IS `name` (a direct generic
/// argument, e.g. the `E` in `Contiguous<E>`) or itself nests `name` deeper
/// (e.g. the `E` in `Wrapper<Contiguous<E>>`).
private func genericArgumentsBind(
    _ name: Swift.String,
    _ clause: GenericArgumentClauseSyntax?
) -> Swift.Bool {
    guard let clause else { return false }
    for argument in clause.arguments {
        guard let argumentType = argument.argument.as(TypeSyntax.self) else { continue }
        if let identifier = argumentType.as(IdentifierTypeSyntax.self), identifier.name.text == name
        {
            return true
        }
        if usedAsGenericArgument(name, in: argumentType) { return true }
    }
    return false
}
