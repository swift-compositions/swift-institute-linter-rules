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

// swiftlint:disable no_try_optional no_existential_throws
// REASON: this rule's own doc comment and diagnostic message must literally cite the
// `try?` pattern it detects, and (in the untyped-callee carve-out) the
// `do throws(any Error)` dead end it names — self-referential fixture shape
// (rule-exemptions skill); the regex-based no_try_optional and
// no_existential_throws rules cannot distinguish prose citation from live code.
/// `try?` swallows typed errors.
///
/// `try?` converts a thrown error into a `nil` Optional, erasing both the
/// error type and the error instance. The institute convention prefers
/// typed throws (`throws(E)`) so the error path remains explicit and
/// recoverable. Past failure mode: `try? input.advance()` swallowed
/// `EAGAIN` causing the Linux hot-spin in the IO Notification.wait()
/// site (see `feedback_prefer_typed_throws_over_try_optional`).
///
/// AST shape: `TryExprSyntax` whose `questionOrExclamationMark.tokenKind`
/// is `.postfixQuestionMark`.
extension Lint.Rule {
    public static let `try optional` = Lint.Rule(
        id: "try optional",
        default: .warning,
        controls: [
            .init(
                id: "try optional erased failure",
                source: "let value = try? load()",
                path: "Sources/Try Consumer/OptionalTry.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "try optional propagating try",
                source: "let value = try load()",
                path: "Sources/Try Consumer/PropagatingTry.swift",
                expectation: .clean
            ),
            .init(
                id: "try optional forced try",
                source: "let value = try! load()",
                path: "Sources/Try Consumer/ForcedTry.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = TryOptionalVisitor(
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
internal let tryOptionalMessage: Swift.String =
    "[try optional] feedback_prefer_typed_throws_over_try_optional: "
    + "`try?` swallows the thrown error and returns `nil`, erasing both the error type "
    + "and the error instance. Prefer typed throws (`throws(E)`) so the error path stays "
    + "explicit and recoverable. Past incident: `try? input.advance()` swallowed `EAGAIN` "
    + "causing the Linux hot-spin in the IO Notification.wait() site. If you genuinely "
    + "want to discard the error AND the callee's error is TYPED, use "
    + "`do throws(E) { ... } catch { }` so the discard is local and visible. If the "
    + "callee throws UNTYPED (cross-module APIs such as `FileManager.removeItem(at:)` "
    + "or `try await task.value`), no construct satisfies every rule: bare "
    + "`do { ... } catch { }` fires [IMPL-075], `do throws(any Error)` fires "
    + "feedback_no_existential_throws, and `do throws(E)` does not compile because "
    + "there is no `E`. Keep the `try?` and apply "
    + "`// swift-linter:disable:next try optional` with a "
    + "`// REASON:` naming the untyped callee — that case is the author's to judge, "
    + "because a per-file rule can prove a callee typed but never untyped."
// swiftlint:enable no_try_optional no_existential_throws

internal final class TryOptionalVisitor: SyntaxVisitor {
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

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        guard let mark = node.questionOrExclamationMark,
            mark.tokenKind == .postfixQuestionMark
        else {
            return .visitChildren
        }
        let location = converter.location(for: mark.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "try optional",
                message: tryOptionalMessage
            )
        )
        return .visitChildren
    }
}
