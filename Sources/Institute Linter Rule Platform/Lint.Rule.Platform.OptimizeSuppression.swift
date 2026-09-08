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

/// Optimization-suppression attributes used as crash-workarounds —
/// `@_optimize(none)`, `@_optimize(size)`, and `@_semantics("optimize.no.*")`
/// — MUST NOT appear on declarations in institute Sources/ or Tests/.
///
/// The attribute masks a SIL-optimizer scalability bug AND is itself a
/// teardown-miscompile risk in `-O` modules (compiler-bug catalog §A19).
/// The only sanctioned escape is an explicit
/// `// swift-linter:disable:next optimize suppression attribute` directive
/// carrying a `// REASON:` continuation with a dossier / catalog-§ citation
/// — there is no implicit carve-out.
///
/// Citation: `[ISSUE-008]` (compiler-bug catalog §A19).
extension Lint.Rule {
    public static let `optimize suppression attribute` = Lint.Rule(
        id: "optimize suppression attribute",
        default: .warning,
        controls: [
            .init(
                id: "optimize suppression attribute optimize none",
                source: "@_optimize(none) func run() {}",
                path: "Sources/Platform Core/SuppressedOptimization.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "optimize suppression attribute inline never",
                source: "@inline(never) func run() {}",
                path: "Sources/Platform Core/InlineControl.swift",
                expectation: .clean
            ),
            .init(
                id: "optimize suppression attribute string boundary",
                source: #"let example = "@_optimize(none) func run() {}""#,
                path: "Tests/Platform Tests/OptimizationExample.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = PlatformOptimizeSuppressionVisitor(
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
internal let platformOptimizeSuppressionMessage: Swift.String =
    "[optimize suppression attribute] [ISSUE-008]: optimization-suppression "
    + "attribute (`@_optimize(none)`, `@_optimize(size)`, or "
    + "`@_semantics(\"optimize.no.*\")`) used as a crash-workaround. The "
    + "attribute masks a SIL-optimizer scalability bug AND is itself a "
    + "teardown-miscompile risk in `-O` modules (compiler-bug catalog §A19). "
    + "Remove the workaround attribute. If it must stay, apply "
    + "`// swift-linter:disable:next optimize suppression attribute` with a "
    + "`// REASON: <dossier / catalog-§ citation>` continuation."

/// The concatenated simple-segment text of a `_semantics` attribute's leading
/// string-literal argument, or `nil` when the attribute has no leading string
/// argument (or that literal contains interpolation). The `_semantics`
/// argument list is parsed as a plain labeled-expression list (the attribute
/// is not special-cased by the parser).
internal func platformOptimizeSuppressionSemanticsString(
    _ node: AttributeSyntax
) -> Swift.String? {
    guard case .argumentList(let arguments)? = node.arguments,
        let first = arguments.first,
        let literal = first.expression.as(StringLiteralExprSyntax.self)
    else { return nil }
    var value = ""
    for segment in literal.segments {
        guard let simple = segment.as(StringSegmentSyntax.self) else { return nil }
        value += simple.content.text
    }
    return value
}

internal final class PlatformOptimizeSuppressionVisitor: SyntaxVisitor {
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

    // Visiting `AttributeSyntax` directly catches the attribute on ANY
    // declaration kind — functions, accessors, inits, subscripts, vars, types
    // — without a per-decl dispatch table.
    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.attributeName.trimmedDescription
        if name == "_optimize" {
            // `@_optimize(none)` / `@_optimize(size)` fire. `@_optimize(speed)`
            // exists and deliberately does not fire — only `none` and `size`
            // suppress optimization.
            if let arguments = node.arguments {
                let mode = arguments.trimmedDescription
                if mode == "none" || mode == "size" {
                    emit(at: node)
                }
            }
        } else if name == "_semantics" {
            // `@_semantics("optimize.no.<anything>")` fires; other `_semantics`
            // strings do not.
            if let value = platformOptimizeSuppressionSemanticsString(node),
                value.hasPrefix("optimize.no.")
            {
                emit(at: node)
            }
        }
        return .visitChildren
    }

    private func emit(at node: AttributeSyntax) {
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
                identifier: "optimize suppression attribute",
                message: platformOptimizeSuppressionMessage
            )
        )
    }
}
