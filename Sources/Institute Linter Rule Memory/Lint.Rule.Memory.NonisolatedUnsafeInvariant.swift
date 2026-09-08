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

/// Wave 3 Thread 7 (2026-05-11) — `nonisolated(unsafe)` declarations
/// MUST carry an adjacent `// SAFETY: ...` or `// WHY: ...` invariant
/// comment that cites the encapsulation guarantee in prose.
///
/// Citation: `[MEM-SAFE-025a]` (memory-safety skill, the safety-isolation note).
///
/// Replaces `Lint.Rule.Memory.NonisolatedUnsafeSafe` (the original
/// `[MEM-SAFE-025]` rule, SUPERSEDED 2026-05-11 by the
/// invariant-comment + `@safe`-forbidden split per
/// the MEM-SAFE-025 reconciliation note).
///
/// The comment MUST be immediately adjacent to the declaration: a
/// blank line between the comment and the `nonisolated(unsafe)` token
/// breaks adjacency and the rule fires. First-line-prefix convention:
/// multi-line blocks may carry `// SAFETY:` or `// WHY:` on only the
/// FIRST line of the block with continuation comments below; the
/// prefix on any line of the contiguous comment block is sufficient
/// to assert the invariant. Intervening `// swift-linter:disable:next ...`
/// directives are walked through.
extension Lint.Rule {
    public static let `nonisolated unsafe without invariant` = Lint.Rule(
        id: "nonisolated unsafe without invariant",
        default: .warning,
        controls: [
            .init(
                id: "nonisolated unsafe without invariant missing",
                source: "nonisolated(unsafe) let sentinel: UnsafeMutableRawPointer = .allocate(capacity: 0)",
                path: "Sources/Memory Core/MissingUnsafeInvariant.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "nonisolated unsafe without invariant documented",
                source: "// SAFETY: Allocated once and never mutated.\nnonisolated(unsafe) let sentinel: UnsafeMutableRawPointer = .allocate(capacity: 0)",
                path: "Sources/Memory Core/DocumentedUnsafeInvariant.swift",
                expectation: .clean
            ),
            .init(
                id: "nonisolated unsafe without invariant isolated",
                source: "let value: Int = 0",
                path: "Sources/Memory Core/IsolatedValue.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = MemoryNonisolatedUnsafeInvariantVisitor(
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
internal let memoryNonisolatedUnsafeInvariantMessage: Swift.String =
    "[nonisolated unsafe without invariant] [MEM-SAFE-025a]: `nonisolated(unsafe)` "
    + "declarations MUST carry an adjacent `// SAFETY:` or `// WHY:` comment "
    + "citing the encapsulation invariant (allocated once / never mutated post-init / "
    + "sync mechanism / ownership discipline). The comment MUST immediately precede "
    + "the declaration with no intervening blank line. Multi-line blocks are accepted "
    + "with the `// SAFETY:` or `// WHY:` prefix on any line of the contiguous block "
    + "(typically the first line); continuation lines need no prefix."

internal final class MemoryNonisolatedUnsafeInvariantVisitor: SyntaxVisitor {
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

    private func hasNonisolatedUnsafe(_ modifiers: DeclModifierListSyntax) -> Bool {
        for modifier in modifiers {
            if modifier.name.tokenKind == .keyword(.nonisolated) {
                if let detail = modifier.detail {
                    // detail is `(unsafe)` — match by trimmed text.
                    if detail.detail.text == "unsafe" {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Returns `true` if the variable declaration's leading trivia
    /// contains an adjacent `// SAFETY:` or `// WHY:` line. See
    /// `memoryTriviaHasAdjacentComment(_:matching:)` in Shared.swift for
    /// the walk's semantics.
    private func hasAdjacentInvariantComment(_ trivia: Trivia) -> Bool {
        memoryTriviaHasAdjacentComment(trivia) { body in
            body.hasPrefix("SAFETY:") || body.hasPrefix("WHY:")
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasNonisolatedUnsafe(node.modifiers) else {
            return .visitChildren
        }
        // The relevant leading trivia is the one on the first token
        // of the declaration. For a variable decl that's the first
        // attribute or modifier — `node.leadingTrivia` resolves to
        // that.
        let trivia = node.leadingTrivia
        if hasAdjacentInvariantComment(trivia) {
            return .visitChildren
        }
        let location = converter.location(
            for: node.bindingSpecifier.positionAfterSkippingLeadingTrivia
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
                identifier: "nonisolated unsafe without invariant",
                message: memoryNonisolatedUnsafeInvariantMessage
            )
        )
        return .visitChildren
    }
}
