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

/// Compile-time-constant `Index`/`Tagged` construction of the form
/// `Index<…>(Ordinal(UInt(<literal>)))` MUST be written as the bare integer
/// literal — the tagged SLI carve-out
/// (`Tagged: ExpressibleByIntegerLiteral`) makes literals infer. Runtime
/// bindings keep the explicit construction. Citation: `[IDX-019]`.
extension Lint.Rule {
    public static let `sli literal` = Lint.Rule(
        id: "sli literal",
        default: .warning,
        controls: [
            .init(
                id: "sli literal Index literal",
                source: "func read(slab: Slab) { _ = slab[Index<Int>(Ordinal(UInt(0)))] }",
                path: "Sources/Idiom Core/IndexLiteral.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "sli literal bare literal",
                source: "func read(slab: Slab) { _ = slab[0] }",
                path: "Sources/Idiom Core/BareLiteral.swift",
                expectation: .clean
            ),
            .init(
                id: "sli literal runtime",
                source: "func read(slot: UInt) { _ = Index<Int>(Ordinal(UInt(slot))) }",
                path: "Sources/Idiom Core/RuntimeIndex.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = IdiomSliLiteralVisitor(
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
internal let idiomSliLiteralMessage: Swift.String =
    "[sli literal] [IDX-019]: verbose compile-time-constant "
    + "`Index`/`Tagged` construction wraps an integer literal in "
    + "`Ordinal(UInt(…))`. The tagged SLI carve-out "
    + "(`Tagged: ExpressibleByIntegerLiteral`) makes literals infer — "
    + "write the bare integer literal (e.g. `slab[0]`). Keep the explicit "
    + "`Index<Element>(Ordinal(UInt(x)))` construction only for runtime "
    + "values (identifiers, member accesses, call results)."

/// The callee name of an outer `Index`/`Tagged` construction: either a bare
/// `DeclReferenceExprSyntax` or a `GenericSpecializationExprSyntax` over one
/// (any generic arguments).
internal func idiomSliOuterCalleeName(_ call: FunctionCallExprSyntax) -> Swift.String? {
    let callee = call.calledExpression
    if let reference = callee.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    if let specialization = callee.as(GenericSpecializationExprSyntax.self),
        let reference = specialization.expression.as(DeclReferenceExprSyntax.self)
    {
        return reference.baseName.text
    }
    return nil
}

/// The callee name of an inner `Ordinal`/`UInt` wrapper — a bare
/// `DeclReferenceExprSyntax` only.
internal func idiomSliBareCalleeName(_ call: FunctionCallExprSyntax) -> Swift.String? {
    call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
}

/// The single unlabeled argument expression of a call, or `nil` when the call
/// does not have exactly one argument with no label (and no trailing closure).
/// A labeled argument (e.g. `Index(_unchecked: …)`) yields `nil` — that is a
/// different API surface ([CONV-015]).
internal func idiomSliSingleUnlabeledArgument(_ call: FunctionCallExprSyntax) -> ExprSyntax? {
    guard call.trailingClosure == nil,
        call.additionalTrailingClosures.isEmpty,
        call.arguments.count == 1,
        let only = call.arguments.first,
        only.label == nil
    else { return nil }
    return only.expression
}

internal final class IdiomSliLiteralVisitor: SyntaxVisitor {
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

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Outer call: `Index(…)` or `Tagged(…)`, bare or generic-specialized.
        guard let outerName = idiomSliOuterCalleeName(node),
            outerName == "Index" || outerName == "Tagged",
            // Exactly one unlabeled argument (no `_unchecked:` surface).
            let ordinalArgument = idiomSliSingleUnlabeledArgument(node),
            // That argument is `Ordinal(<x>)`.
            let ordinalCall = ordinalArgument.as(FunctionCallExprSyntax.self),
            idiomSliBareCalleeName(ordinalCall) == "Ordinal",
            let uintArgument = idiomSliSingleUnlabeledArgument(ordinalCall),
            // `<x>` is `UInt(<y>)`.
            let uintCall = uintArgument.as(FunctionCallExprSyntax.self),
            idiomSliBareCalleeName(uintCall) == "UInt",
            let innerArgument = idiomSliSingleUnlabeledArgument(uintCall),
            // `<y>` is an integer literal — SLI is literals-only; runtime
            // bindings (identifier / member-access / call) are exempt.
            innerArgument.is(IntegerLiteralExprSyntax.self)
        else { return .visitChildren }

        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "sli literal",
                message: idiomSliLiteralMessage
            )
        )
        return .visitChildren
    }
}
