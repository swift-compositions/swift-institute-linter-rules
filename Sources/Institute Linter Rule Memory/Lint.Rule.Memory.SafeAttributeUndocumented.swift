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

/// Option B DECISION (2026-05-12) — every `@safe`-attributed declaration
/// in `Sources/` MUST carry an adjacent invariant disclosure: either a
/// `// SAFETY:` / `// WHY:` line-comment block OR a `## Safety Invariant`
/// section within an adjacent doc-comment.
///
/// Citation: `[MEM-SAFE-025b]` (admits `@safe`) and `[MEM-SAFE-025c]`
/// (the disclosure requirement); both in the memory-safety skill,
/// the safety-isolation note.
///
/// Inverted from `Lint.Rule.Memory.SafeForbidden` (Wave 3 Thread 7 +
/// Wave 4 absorber-pattern carve-out). The pre-Option-B rule fired
/// whenever `@safe` appeared and admitted it only under a tool-capability-
/// bound carve-out predicate. The inverted rule admits `@safe` per
/// SE-0458's intent on any decl form (struct, class, enum, actor,
/// extension, func, var, let, init, subscript, typealias, associated
/// type) and fires only when the adjacent invariant disclosure is
/// missing.
///
/// Cross-language convention (Rust `unsafe` + `// SAFETY:`, Haskell Safe
/// extensions + haddocks, proof-carrying-code's witness + obligation
/// pair): safety claims use both a machine-checkable attribute and a
/// human-auditable explanation. This rule policies the explanation
/// half; SE-0458 polices the claim half. See
/// the safe-attribute absorber pattern fundamentals note
/// v1.1.0 DECISION (Option B) for the full prior-art survey and the
/// rationale for the inversion.
///
/// The `// SAFETY:` / `// WHY:` and `## Safety Invariant` adjacency
/// helpers are preserved from the previous `SafeForbidden` rule (Wave 4
/// commit `cbf4922`'s trivia walker). Only the gating semantics flip:
/// presence of a disclosure now ADMITS rather than COMPLEMENTING a
/// separate condition.
extension Lint.Rule {
    public static let `safe attribute undocumented` = Lint.Rule(
        id: "safe attribute undocumented",
        default: .warning,
        controls: [
            .init(
                id: "safe attribute undocumented missing",
                source: "@safe public struct Storage {}",
                path: "Sources/Memory Core/UndocumentedSafe.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "safe attribute undocumented disclosed",
                source: "// SAFETY: Safe by construction.\n@safe public struct Storage {}",
                path: "Sources/Memory Core/DocumentedSafe.swift",
                expectation: .clean
            ),
            .init(
                id: "safe attribute undocumented outside sources",
                source: "@safe public struct Storage {}",
                path: "Tests/Memory Tests/SafeFixture.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            // Scope: the header doc and the message both assert this rule
            // applies to every `@safe`-attributed declaration IN `Sources/`
            // — a file outside any `Sources/` path component (README
            // snippets embedded as fixtures, `Tests/`, `Experiments/`,
            // `Examples/`, a bare top-level script) is out of scope. Mirrors
            // the inclusion/exclusion path-scoping convention used by
            // `pointer advanced by` (`Lint.Rule.Memory.PointerArithmetic.swift`),
            // adapted to an inclusion check since this rule's scope is
            // phrased positively ("in Sources/") rather than as an
            // exclusion list.
            let path = source.file.filePath
            guard path.hasPrefix("Sources/") || path.contains("/Sources/") else {
                return []
            }
            let visitor = MemorySafeAttributeUndocumentedVisitor(
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
internal let memorySafeAttributeUndocumentedMessage: Swift.String =
    "[safe attribute undocumented] [MEM-SAFE-025c]: every `@safe`-attributed "
    + "declaration MUST carry an adjacent invariant disclosure — either a "
    + "`// SAFETY:` / `// WHY:` line-comment block in the declaration's "
    + "leading trivia, OR a `## Safety Invariant` section within an adjacent "
    + "`///` doc-comment. The disclosure SHOULD cite a [MEM-SAFE-024] "
    + "Category (A/B/C/D) when applicable; multi-line free-form prose is "
    + "acceptable when the site is not categorizable. Adjacency means no "
    + "blank line between the disclosure and the declaration token. "
    + "Per [MEM-SAFE-025b], `@safe` is admitted on any declaration in "
    + "`Sources/` (SE-0458's intent); this rule polices the institute "
    + "disclosure requirement layered on top."

internal final class MemorySafeAttributeUndocumentedVisitor: SyntaxVisitor {
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

    // MARK: - @safe attribute detection

    /// Returns the first `@safe` attribute syntax in `attributes`,
    /// or `nil` if none is present. Used as both the gate and the
    /// finding-location source.
    private func safeAttribute(in attributes: AttributeListSyntax) -> AttributeSyntax? {
        for attribute in attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            if attr.attributeName.trimmedDescription == "safe" {
                return attr
            }
        }
        return nil
    }

    private func emit(at attribute: AttributeSyntax) {
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
                identifier: "safe attribute undocumented",
                message: memorySafeAttributeUndocumentedMessage
            )
        )
    }

    // MARK: - Adjacent invariant disclosure check
    //
    // The disclosure may sit:
    //   - In the decl's leading trivia (BEFORE `@safe`).
    //   - Between `@safe` and the next attribute/modifier (in the
    //     leading trivia of `public` / the type keyword / the binding
    //     specifier / the function `func` keyword / etc.).
    //
    // We check each token's leading trivia from the decl's first token
    // up to and including the decl's primary keyword token. Each
    // token's trivia is checked INDEPENDENTLY for adjacency — we don't
    // merge them, because `newlines(N)` adjacency only makes sense
    // within a single contiguous trivia block.

    /// True iff any of the adjacent trivia blocks contains a
    /// `// SAFETY:` / `// WHY:` line-comment block in adjacent
    /// position, OR a `## Safety Invariant` doc-comment section in
    /// adjacent position.
    private func hasAdjacentInvariantDisclosure<D: DeclSyntaxProtocol>(
        node: D,
        keywordToken: TokenSyntax
    ) -> Bool {
        for trivia in adjacentTriviaBlocks(node: node, keywordToken: keywordToken) {
            if triviaHasInvariantLineComment(trivia)
                || triviaHasSafetyInvariantDocSection(trivia)
            {
                return true
            }
        }
        return false
    }

    /// Collect the leading trivia of each token from the decl's first
    /// token to the keyword token (inclusive). Each block is a
    /// coherent SwiftSyntax `Trivia` value with its own newline
    /// counts; we never merge across blocks.
    private func adjacentTriviaBlocks<D: DeclSyntaxProtocol>(
        node: D,
        keywordToken: TokenSyntax
    ) -> [Trivia] {
        var blocks: [Trivia] = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            blocks.append(token.leadingTrivia)
            if token == keywordToken { break }
        }
        return blocks
    }

    // MARK: - Invariant line-comment matcher

    /// True if the trivia contains a `// SAFETY:` or `// WHY:` line
    /// (case-insensitive on the keyword), in an adjacent comment block.
    /// Non-invariant line comments (e.g. `// WHEN TO REMOVE:`,
    /// `// TRACKING:`) within the adjacent block are tolerated — the
    /// institute idiom mixes invariant disclosure with metadata comments.
    ///
    /// Category citation is NOT required here (SHOULD-strength per
    /// [MEM-SAFE-025c]); free-form prose is acceptable when the site
    /// isn't categorizable. The matcher only checks for the
    /// `// SAFETY:` or `// WHY:` prefix. See
    /// `memoryTriviaHasAdjacentComment(_:matching:)` in Shared.swift for
    /// the walk's semantics.
    private func triviaHasInvariantLineComment(_ trivia: Trivia) -> Bool {
        memoryTriviaHasAdjacentComment(trivia) { body in
            isInvariantPrefix(body[...])
        }
    }

    /// `true` if the comment body begins with `WHY:` or `SAFETY:`
    /// (case-insensitive on the keyword).
    private func isInvariantPrefix(_ body: Swift.Substring) -> Bool {
        let lower = body.lowercased()
        return lower.hasPrefix("why:") || lower.hasPrefix("safety:")
    }

    // MARK: - Safety-invariant doc-section matcher

    /// True if the trivia contains a doc-comment block whose body
    /// includes the literal heading `## Safety Invariant`. A blank
    /// line (single `newlines(N)` with `N >= 2`) between the doc
    /// block and the rest of the trivia breaks adjacency.
    ///
    /// Non-doc line comments (`// WHEN TO REMOVE:` etc.) are tolerated
    /// in the adjacent block — the institute idiom mixes both.
    private func triviaHasSafetyInvariantDocSection(_ trivia: Trivia) -> Bool {
        let pieces = Swift.Array(trivia)
        var collected: [Swift.String] = []
        // Same accumulation discipline as `triviaHasInvariantLineComment`:
        // a whitespace-only blank line is two newline-like pieces
        // separated only by spaces/tabs, and must break adjacency exactly
        // as a single `newlines(2)` piece would.
        var newlineRun = 0

        for piece in pieces.reversed() {
            switch piece {
            case .newlines(let count), .carriageReturns(let count),
                .carriageReturnLineFeeds(let count):
                newlineRun += count
                if newlineRun >= 2 {
                    return matchesSafetyInvariant(in: collected)
                }

            case .docLineComment(let text):
                newlineRun = 0
                collected.append(text)

            case .docBlockComment(let text):
                newlineRun = 0
                collected.append(text)

            case .lineComment, .blockComment:
                // Non-doc comments are tolerated — keep walking, the
                // doc-block might be earlier.
                newlineRun = 0
                continue

            case .spaces, .tabs:
                continue

            default:
                continue
            }
        }
        return matchesSafetyInvariant(in: collected)
    }

    private func matchesSafetyInvariant(in pieces: [Swift.String]) -> Bool {
        for text in pieces {
            if text.contains("## Safety Invariant") {
                return true
            }
        }
        return false
    }

    // MARK: - Type-decl visitors

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.structKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.classKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.enumKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.actorKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.extensionKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.protocolKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    // MARK: - Non-type-decl visitors (now admitted under [MEM-SAFE-025b])

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.bindingSpecifier) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.funcKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.initKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.deinitKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.subscriptKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.typealiasKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let safeAttr = safeAttribute(in: node.attributes) else {
            return .visitChildren
        }
        if !hasAdjacentInvariantDisclosure(node: node, keywordToken: node.associatedtypeKeyword) {
            emit(at: safeAttr)
        }
        return .visitChildren
    }
}
