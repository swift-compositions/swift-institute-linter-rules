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

/// `typealias X = Y.Z` (with X != Z) is a rename-bridge anti-pattern.
/// Citation: `[API-NAME-004]`.
extension Lint.Rule {
    public static let `unification typealias` = Lint.Rule(
        id: "unification typealias",
        default: .warning,
        controls: [
            .init(
                id: "unification typealias different leaf",
                source: "public typealias SourceLocation = Text.Location",
                path: "Sources/Naming Core/DifferentLeaf.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "unification typealias same leaf",
                source: "public typealias Event = Kernel.Event",
                path: "Sources/Naming Core/SameLeaf.swift",
                expectation: .clean
            ),
            .init(
                id: "unification typealias swift bridge",
                source: "public typealias Protocol = Swift.Equatable",
                path: "Sources/Naming Core/SwiftBridge.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingUnificationTypealiasVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingUnificationTypealiasMessage: Swift.String =
    "[unification typealias] [API-NAME-004]: typealias renames a "
    + "member type to a different local name. Type unification MUST use the "
    + "canonical type at all call sites; a typealias bridge adds indirection "
    + "without domain value."

internal final class NamingUnificationTypealiasVisitor: SyntaxVisitor {
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
        if member.genericArgumentClause != nil { return .visitChildren }
        let rhsLeaf = member.name.text
        guard rhsLeaf != lhsName else { return .visitChildren }
        // Exempt stdlib bridges: `public typealias Protocol = Swift.Equatable`
        // (Equation/Hash/Comparison primitives under Swift 6.4+ SE-0499) is a
        // namespace alias TO the stdlib, not a rename bridge between two
        // co-equal type definitions. The structural signal is the RHS base
        // identifier resolving to `Swift`.
        if let baseIdentifier = member.baseType.as(IdentifierTypeSyntax.self),
            baseIdentifier.name.text == "Swift"
        {
            return .visitChildren
        }
        // Exempt per [RULE-EXEMPT-3] (conformance-context): typealiases
        // that satisfy an associatedtype requirement of a protocol the
        // enclosing context adopts — `extension X: Y { typealias
        // Underlying = Unicode.Scalar }` declares conformance to `Y`;
        // the LHS name is dictated by `Y`'s associatedtype, the RHS
        // is whatever satisfies it. Forced by the protocol shape, not
        // by a discretionary [API-NAME-004] rename-bridge choice.
        // Helper lives in `Lint.Rule.Naming.Shared.swift`.
        if Naming.isInsideConformingContext(Syntax(node)) {
            return .visitChildren
        }
        // Exempt per [RULE-EXEMPT-5] (Protocol-sentinel): the
        // gerund-as-capability typealias pattern per [PKG-NAME-001]
        // pairs a noun-form namespace (`Carrier`) with a gerund-form
        // capability alias (`Carrying`) so conformance sites read as
        // verb-form predicates (`extension Cardinal: Carrying`). The
        // structural signal is the RHS targeting a member named
        // `Protocol` — the institute sentinel for the [API-IMPL-009]
        // hoisted-protocol pattern. Helper lives in
        // `Lint.Rule.Naming.Shared.swift`.
        if Naming.isProtocolSentinel(rhsLeaf) {
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
                identifier: "unification typealias",
                message: namingUnificationTypealiasMessage
            )
        )
        return .visitChildren
    }
}
