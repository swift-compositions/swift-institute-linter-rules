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

/// A new enum case is handled explicitly; `@unknown default` is not
/// added.
///
/// The compile-time signal is the asset: source-additive at the type
/// level is not source-compatible at the switch level, and `@unknown
/// default` trades the missed-case error for a runtime fallthrough.
/// This convention runs against widely published external guidance, so
/// the construct is added in good faith by contributors who have not
/// read the house convention.
///
/// The rule fires on each `@unknown default` clause in a `switch`. The
/// canonical fix is explicit case handling: enumerate the cases the
/// `switch` must decide and let the compiler flag additions.
///
/// Citation: `swift-institute-linter-rules#4`.
extension Lint.Rule {
    public static let `unknown default` = Lint.Rule(
        id: "unknown default",
        default: .warning,
        controls: [
            .init(
                id: "unknown default annotated",
                source: "func classify(value: Value) { switch value { case .byte: break; @unknown default: break } }",
                path: "Sources/Idiom Core/UnknownDefault.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "unknown default explicit cases",
                source: "func classify(value: Value) { switch value { case .byte: break; case .other: break } }",
                path: "Sources/Idiom Core/ExplicitCases.swift",
                expectation: .clean
            ),
            .init(
                id: "unknown default plain",
                source: "func classify(value: Value) { switch value { case .byte: break; default: break } }",
                path: "Sources/Idiom Core/PlainDefault.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = IdiomUnknownDefaultVisitor(
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
internal let idiomUnknownDefaultMessage: Swift.String =
    "[unknown default]: handle new enum cases explicitly instead of "
    + "adding `@unknown default` — the compile-time missed-case signal is "
    + "the asset, and `@unknown default` trades it for a runtime "
    + "fallthrough."

internal final class IdiomUnknownDefaultVisitor: SyntaxVisitor {
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

    /// A bare `_` in a case-item pattern position parses as either
    /// `WildcardPatternSyntax` or an `ExpressionPatternSyntax` wrapping a
    /// `DiscardAssignmentExprSyntax` — expression/pattern grammar is
    /// ambiguous at parse time, so both shapes occur depending on
    /// context. Recognize both.
    private func isWildcard(_ pattern: PatternSyntax) -> Swift.Bool {
        if pattern.is(WildcardPatternSyntax.self) { return true }
        if let expressionPattern = pattern.as(ExpressionPatternSyntax.self) {
            return expressionPattern.expression.is(DiscardAssignmentExprSyntax.self)
        }
        return false
    }

    /// `@unknown case _:` is the same `[IDIOM-...]` runtime-fallthrough
    /// shape as `@unknown default:` — it is only spelled as a wildcard
    /// case rather than the `default` keyword. Recognize both.
    private func isDefaultLikeLabel(_ label: SwitchCaseSyntax.Label) -> Swift.Bool {
        if case .default = label { return true }
        if case .case(let caseLabel) = label {
            return caseLabel.caseItems.allSatisfy { isWildcard($0.pattern) }
        }
        return false
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        guard
            let attribute = node.attribute,
            attribute.attributeName.trimmedDescription == "unknown",
            isDefaultLikeLabel(node.label)
        else {
            return .visitChildren
        }
        let location = converter.location(for: attribute.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "unknown default",
                message: idiomUnknownDefaultMessage
            )
        )
        return .visitChildren
    }
}
