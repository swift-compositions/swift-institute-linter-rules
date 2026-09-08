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

/// Wave 4 (mechanization-program) — `typealias X = Y.X` is the
/// namespace-adoption shape: the higher-layer namespace adopts a
/// lower-layer concept under the same leaf name.
///
/// The recognizer skips two well-defined cases where the same-leaf
/// typealias is structurally dictated rather than a discretionary rename
/// bridge:
///
/// 1. Conforming-context associatedtype satisfier — `extension X: Y {
///    typealias Z = W.Z }` declares conformance to `Y`; the same-leaf
///    typealias satisfies an associatedtype requirement, not a rename.
/// 2. Parameterized adoption idiom — a GENERIC typealias that forwards its
///    own generic parameter(s) into the RHS specialization AND binds at
///    least one additional argument (the enclosing Self-type or a concrete
///    type). This is how an institute consumer adopts a parameterized
///    capability, e.g. `extension Stack { typealias Property<Tag> =
///    Property.Property<Tag, Stack<Element>> }`, which sugars
///    `Stack.Property<Push>` to the two-parameter underlying generic. The
///    self-binding distinguishes it from a bare rename bridge (no generics
///    / pure passthrough), which the rule still flags.
///
/// Citation: `[API-NAME-004a]` (code-surface skill, naming).
extension Lint.Rule {
    public static let `namespace adoption typealias` = Lint.Rule(
        id: "namespace adoption typealias",
        default: .note,
        controls: [
            .init(
                id: "namespace adoption typealias same leaf",
                source: "public typealias Event = Kernel.Event",
                path: "Sources/Naming Core/SameLeaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "namespace adoption typealias different leaf",
                source: "public typealias SourceLocation = Text.Location",
                path: "Sources/Naming Core/DifferentLeaf.swift",
                expectation: .clean
            ),
            .init(
                id: "namespace adoption typealias conforming context",
                source: "extension Tagged: Collection { public typealias Index = Underlying.Index }",
                path: "Sources/Naming Core/ConformingContext.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingNamespaceAdoptionVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingNamespaceAdoptionMessage: Swift.String =
    "[namespace adoption typealias] [API-NAME-004a]: same-leaf typealias is "
    + "the namespace-adoption shape. Confirm the higher-layer namespace "
    + "declares ≥ 5 sibling types / extensions / methods on the adopted "
    + "concept — otherwise this is a rename bridge per [API-NAME-004]. "
    + "Surfaced as a non-counting review prompt. (The parameterized-adoption idiom — a "
    + "generic typealias forwarding its parameter(s) while binding the "
    + "enclosing Self-type into the underlying generic — does not fire.)"

/// A *parameterized namespace-adoption* typealias is a GENERIC typealias
/// whose RHS specialization both (a) forwards at least one of the
/// typealias's own generic parameters and (b) binds at least one additional
/// argument that is NOT a bare LHS parameter (the enclosing Self-type, a
/// concrete type, or a nested generic). This is the institute
/// consumer-adoption idiom — `extension Stack { typealias Property<Tag> =
/// Property.Property<Tag, Stack<Element>> }` — which is a partial
/// application of the underlying two-parameter generic, not a rename. A bare
/// rename bridge (`typealias Event = Kernel.Event`, no generics) and a pure
/// passthrough (`typealias Array<T> = Swift.Array<T>`, every RHS argument is
/// a bare forward) both return `false` here and remain flagged.
private func namingIsParameterizedAdoption(
    _ node: TypeAliasDeclSyntax,
    member: MemberTypeSyntax
) -> Swift.Bool {
    guard let lhsParameters = node.genericParameterClause?.parameters,
        !lhsParameters.isEmpty
    else { return false }
    guard let rhsArguments = member.genericArgumentClause?.arguments,
        !rhsArguments.isEmpty
    else { return false }

    var lhsParameterNames: Swift.Set<Swift.String> = []
    for parameter in lhsParameters { lhsParameterNames.insert(parameter.name.text) }

    var forwardsAParameter = false
    var bindsAnExtraArgument = false
    for argument in rhsArguments {
        if let identifier = argument.argument.as(IdentifierTypeSyntax.self),
            identifier.genericArgumentClause == nil,
            lhsParameterNames.contains(identifier.name.text)
        {
            forwardsAParameter = true
        } else {
            bindsAnExtraArgument = true
        }
    }
    return forwardsAParameter && bindsAnExtraArgument
}

internal final class NamingNamespaceAdoptionVisitor: SyntaxVisitor {
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

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let lhsName = node.name.text
        guard let member = node.initializer.value.as(MemberTypeSyntax.self) else {
            return .visitChildren
        }
        let rhsLeaf = member.name.text
        guard rhsLeaf == lhsName else { return .visitChildren }
        // Exempt typealiases declared inside a context that introduces
        // protocol conformance — `extension Tagged: Collection where ...
        // { typealias Index = Underlying.Index }`. The same-leaf typealias
        // is satisfying an associatedtype requirement of the adopted
        // protocol, not a discretionary namespace-adoption choice. The
        // structural signal is a non-empty inheritance clause on the
        // enclosing extension or type declaration.
        if Naming.isInsideConformingContext(Syntax(node)) {
            return .visitChildren
        }
        // Exempt the parameterized namespace-adoption idiom (binds the
        // enclosing Self-type into the underlying generic — institute
        // consumer-adoption shape, not a rename bridge).
        if namingIsParameterizedAdoption(node, member: member) {
            return .visitChildren
        }
        let location = converter.location(
            for: node.typealiasKeyword.positionAfterSkippingLeadingTrivia
        )
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "namespace adoption typealias",
                message: namingNamespaceAdoptionMessage
            )
        )
        return .visitChildren
    }
}
