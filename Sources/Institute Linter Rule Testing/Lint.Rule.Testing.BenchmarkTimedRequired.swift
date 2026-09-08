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

/// Performance-suite `@Test` functions MUST carry the `.timed()` trait — OR the
/// enclosing suite/function carries the `[BENCH-003]` executable-variant citation
/// in its leading trivia (the sanctioned instrument for L1-isolated trees whose
/// dependency closure cannot reach the `.timed()` stack: measurement lives in a
/// nested `Benchmarks/` executable; in-test Performance suites are then
/// load-scale GATES, exempt when citing the variant).
/// Citation: `[BENCH-003]`.
extension Lint.Rule {
    public static let `benchmark timed required` = Lint.Rule(
        id: "benchmark timed required",
        default: .warning,
        observe: Lint.Rule.measured { source, severity in
            let visitor = TestingBenchmarkTimedRequiredVisitor(
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
internal let testingBenchmarkTimedRequiredMessage: Swift.String =
    "[benchmark timed required] [BENCH-003]: `@Test` functions inside a "
    + "`Performance` suite MUST carry the `.timed()` trait. Without it, the "
    + "performance test runs once with no measurement structure. Where the "
    + ".timed() stack is unreachable (L1-isolated trees), the sanctioned "
    + "executable-variant instrument applies — measure in the nested "
    + "Benchmarks/ package and mark this suite with a `[BENCH-003]` variant "
    + "citation comment to exempt it."

/// Structural check for the `.timed(...)` trait argument (#24 nit:
/// replaces a `.contains(".timed")` textual scan of the whole
/// attribute's description, which also matches inside an unrelated
/// interior comment or string, or a differently-named trait that
/// merely contains the substring). `.timed` is always invoked with
/// parens per its own documented shape, so the argument must be a
/// call whose called expression is the bare `.timed` member access.
internal func testingBenchmarkAttributeMentionsTimed(_ attribute: AttributeSyntax) -> Swift.Bool {
    guard case .argumentList(let arguments) = attribute.arguments else { return false }
    for argument in arguments {
        guard let call = argument.expression.as(FunctionCallExprSyntax.self) else { continue }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self) else { continue }
        if member.declName.baseName.text == "timed" {
            return true
        }
    }
    return false
}

internal final class TestingBenchmarkTimedRequiredVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    var inPerformanceStructDepth: Swift.Int = 0
    var variantExemptDepth: Swift.Int = 0

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func testAttribute(_ attributes: AttributeListSyntax) -> AttributeSyntax? {
        for attribute in attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            let attributeName = attr.attributeName.trimmedDescription
            if attributeName == "Test" || attributeName.hasSuffix(".Test") { return attr }
        }
        return nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "Performance" {
            inPerformanceStructDepth += 1
            if citesVariant(node.leadingTrivia) { variantExemptDepth += 1 }
        }
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        if node.name.text == "Performance" {
            inPerformanceStructDepth -= 1
            if citesVariant(node.leadingTrivia) { variantExemptDepth -= 1 }
        }
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let last = node.extendedType.trimmedDescription.split(separator: ".").last,
            Swift.String(last) == "Performance"
        {
            inPerformanceStructDepth += 1
            if citesVariant(node.leadingTrivia) { variantExemptDepth += 1 }
        }
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        if let last = node.extendedType.trimmedDescription.split(separator: ".").last,
            Swift.String(last) == "Performance"
        {
            inPerformanceStructDepth -= 1
            if citesVariant(node.leadingTrivia) { variantExemptDepth -= 1 }
        }
    }

    /// The executable-variant citation carve ([BENCH-003], rule-exemptions
    /// citation-comment shape): `[BENCH-003]` in the decl's leading trivia.
    private func citesVariant(_ trivia: Trivia) -> Swift.Bool {
        for piece in trivia {
            switch piece {
            case .lineComment(let text), .blockComment(let text),
                .docLineComment(let text), .docBlockComment(let text):
                if text.contains("[BENCH-003]") { return true }

            default:
                continue
            }
        }
        return false
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard inPerformanceStructDepth > 0 else { return .visitChildren }
        guard variantExemptDepth == 0 else { return .visitChildren }
        guard let attribute = testAttribute(node.attributes) else { return .visitChildren }
        if citesVariant(node.leadingTrivia) { return .visitChildren }
        if !testingBenchmarkAttributeMentionsTimed(attribute) {
            let location = converter.location(for: node.name.positionAfterSkippingLeadingTrivia)
            matches.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "benchmark timed required",
                    message: testingBenchmarkTimedRequiredMessage
                )
            )
        }
        return .visitChildren
    }
}
