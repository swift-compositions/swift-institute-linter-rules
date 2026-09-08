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

/// `try` inside stdlib `rethrows` higher-order methods MUST be adapted via
/// the `Result<T, E>` shim. Citation: `[IMPL-109]`.
///
/// Coordination note: the same site can also fire `closure typed throws
/// annotation` ([API-ERR-004]) when the closure sits inside a `throws(E)`
/// context, since an un-shimmed `try` on a rethrows method also lacks the
/// explicit annotation that rule wants. The remedies conflict — apply this
/// rule's `Result<T, E>` materialisation first; it removes the bare `try`
/// the annotation rule keys on, so the two do not both need to be
/// satisfied independently at the same site.
extension Lint.Rule {
    public static let `result wrapper for rethrows shim` = Lint.Rule(
        id: "result wrapper for rethrows shim",
        default: .warning,
        controls: [
            .init(
                id: "result wrapper for rethrows shim map try",
                source: "let output = values.map { try transform($0) }",
                path: "Sources/Throws Consumer/RethrowsMap.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "result wrapper for rethrows shim map nonthrowing",
                source: "let output = values.map { transform($0) }",
                path: "Sources/Throws Consumer/NonthrowingMap.swift",
                expectation: .clean
            ),
            .init(
                id: "result wrapper for rethrows shim typed map boundary",
                source: "let output = try values.map { value throws(Read.Error) in "
                    + "try transform(value) }",
                path: "Sources/Throws Consumer/TypedThrowsMap.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ThrowsRethrowsResultShimVisitor(
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
internal let throwsRethrowsResultShimMessage: Swift.String =
    "[result wrapper for rethrows shim] [IMPL-109]: stdlib `rethrows` higher-order "
    + "methods erase typed-throws to `any Error`. Materialise `Result<T, E>` "
    + "inside the closure, return it, and `try result.get()` outside."

@usableFromInline
internal let rethrowsMethodNames: Swift.Set<Swift.String> = [
    "map", "compactMap", "flatMap", "filter", "forEach", "reduce",
    "first", "contains", "allSatisfy", "min", "max",
    "drop", "prefix", "suffix", "split", "sorted",
]

internal final class ThrowsRethrowsResultShimVisitor: SyntaxVisitor {
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

    private func calledMemberName(_ called: ExprSyntax) -> Swift.String? {
        if let memberAccess = called.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return nil
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let name = calledMemberName(node.calledExpression) else { return .visitChildren }
        guard rethrowsMethodNames.contains(name) else { return .visitChildren }
        var closures: [ClosureExprSyntax] = []
        if let trailing = node.trailingClosure { closures.append(trailing) }
        for additional in node.additionalTrailingClosures { closures.append(additional.closure) }
        for argument in node.arguments {
            if let closure = argument.expression.as(ClosureExprSyntax.self) {
                closures.append(closure)
            }
        }
        for closure in closures {
            // Skip closures that carry an explicit typed-throws annotation
            // (`{ ... throws(E) -> R in ... }`). Stdlib `rethrows` higher-
            // order methods accept only untyped-throws closures; an
            // explicitly typed-throws closure literal cannot be invoking
            // stdlib rethrows form (it's an institute typed-throws API
            // like `Tagged.map`). The AST-only heuristic catches the
            // dominant institute case where authors annotate; inferred-
            // throw-type closures (no explicit annotation) fall through
            // to the existing check.
            if throwsIsTypedThrows(closure.signature?.effectSpecifiers?.throwsClause) {
                continue
            }
            let finder = ThrowsRethrowsTryFinder(viewMode: .sourceAccurate)
            finder.walk(closure)
            for position in finder.positions {
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
                        identifier: "result wrapper for rethrows shim",
                        message: throwsRethrowsResultShimMessage
                    )
                )
            }
        }
        return .visitChildren
    }
}
