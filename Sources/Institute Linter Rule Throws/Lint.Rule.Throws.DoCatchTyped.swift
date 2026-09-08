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

/// `do { try ... } catch` MUST use typed-throws specifier
/// `do throws(E) { try ... } catch { }`. Citation: `[IMPL-075]`.
extension Lint.Rule {
    public static let `do throws for typed catch` = Lint.Rule(
        id: "do throws for typed catch",
        default: .warning,
        controls: [
            .init(
                id: "do throws for typed catch bare do try",
                source: "do { try load() } catch { handle(error) }",
                path: "Sources/Throws Consumer/BareDoTry.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "do throws for typed catch typed do",
                source: "do throws(Read.Error) { try load() } catch { handle(error) }",
                path: "Sources/Throws Consumer/TypedDoTry.swift",
                expectation: .clean
            ),
            .init(
                id: "do throws for typed catch optional try",
                source: "do { _ = try? load() } catch { handle(error) }",
                path: "Sources/Throws Consumer/OptionalDoTry.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ThrowsDoCatchTypedVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

// swiftlint:disable no_existential_throws
// REASON: this rule's own diagnostic message must literally cite
// `do throws(any Error)` as the dead-end construct it names in the untyped-callee
// carve-out — self-referential fixture shape (rule-exemptions skill); the
// regex-based no_existential_throws rule cannot distinguish prose citation from
// live code. Re-enabled immediately after the message declaration.
@usableFromInline
internal let throwsDoCatchTypedMessage: Swift.String =
    "[do throws for typed catch] [IMPL-075]: bare `do { try ... } catch { }` "
    + "erases the concrete error type. Use `do throws(E) { try ... } catch { }` "
    + "to preserve `E` in the catch binding."
    + " If the callee throws UNTYPED (cross-module APIs such as "
    + "`FileManager.removeItem(at:)` or `try await task.value`) there is no `E` "
    + "to name and no construct satisfies every rule — `try?` fires "
    + "feedback_prefer_typed_throws_over_try_optional and `do throws(any Error)` "
    + "fires feedback_no_existential_throws. Apply "
    + "`// swift-linter:disable:next do throws for typed catch` with a `// REASON:` "
    + "naming the untyped callee. Where a typed `E` DOES exist both rules are "
    + "satisfiable together, so this rule is not softened for the typed case."
// swiftlint:enable no_existential_throws

internal final class ThrowsDoCatchTypedVisitor: SyntaxVisitor {
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

    override func visit(_ node: DoStmtSyntax) -> SyntaxVisitorContinueKind {
        if node.throwsClause != nil { return .visitChildren }
        guard !node.catchClauses.isEmpty else { return .visitChildren }
        let finder = ThrowsDoCatchTryFinder(viewMode: .sourceAccurate)
        finder.walk(node.body)
        guard finder.found else { return .visitChildren }
        let location = converter.location(for: node.doKeyword.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "do throws for typed catch",
                message: throwsDoCatchTypedMessage
            )
        )
        return .visitChildren
    }
}
