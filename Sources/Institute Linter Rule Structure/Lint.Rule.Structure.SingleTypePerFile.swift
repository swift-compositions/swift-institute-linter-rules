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

internal import Cardinal
public import Lint
internal import SwiftSyntax

/// Wave 2b finalization (2026-05-10) — one type declaration per file.
///
/// Citation: `[API-IMPL-005]` (code-surface skill).
extension Lint.Rule {
    public static let `single type per file` = Lint.Rule(
        id: "single type per file",
        default: .warning,
        controls: [
            .init(
                id: "single type per file two declarations",
                source: "struct First {}\nstruct Second {}",
                path: "Sources/Structure Core/First.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "single type per file one declaration",
                source: "struct First {}",
                path: "Sources/Structure Core/First.swift",
                expectation: .clean
            ),
            .init(
                id: "single type per file test scope",
                source: "struct First {}\nstruct Second {}",
                path: "Tests/Structure Tests/First Tests.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            // Scope-exclusion per Decision 2: skip files whose path has a
            // segment named `Tests`, `Experiments`, or `Examples`.
            let path = source.file.filePath
            for excluded in ["Tests", "Experiments", "Examples"] {
                if path == excluded
                    || path.hasPrefix("\(excluded)/")
                    || path.contains("/\(excluded)/")
                {
                    return []
                }
            }
            let visitor = StructureSingleTypePerFileVisitor(
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
internal let structureSingleTypePerFileMessage: Swift.String =
    "[single type per file] [API-IMPL-005]: each `.swift` source file MUST contain "
    + "exactly one type declaration (`struct`, `class`, `enum`, `actor`, `protocol`). "
    + "Multiple `extension` declarations of the enclosing type are permitted. "
    + "Move additional types to their own files; the file naming convention "
    + "[API-IMPL-006] requires the file name to match the type's nested path."

internal final class StructureSingleTypePerFileVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    var topLevelCount: Cardinal = .zero

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // #28 defect 4: the hand-rolled `currentDepth` counter bumped for
    // struct/class/enum/actor/protocol but never for a function-like
    // container, so a type declared inside a function body was counted
    // at depth 0 — a second top-level type, with a prescribed fix
    // ("move to its own file") that cannot apply to it. Replaced with
    // the structural ancestor walk `structureIsFileSignificant(_:)`
    // (`Lint.Rule.Structure.Shared.swift`), the extension-transparent
    // sibling of `Lint.Syntax.Scope.isTopLevel(_:)` — enumerating
    // container kinds is what produced this defect (and the identical
    // one in #21 blocker 3's `compound platform namespace root`); the
    // ancestor walk does not have a "kind I forgot" failure mode.
    private func handleTypeDecl(_ node: some SyntaxProtocol, at position: AbsolutePosition) {
        guard structureIsFileSignificant(node) else { return }
        topLevelCount += .one
        guard topLevelCount > .one else { return }
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
                identifier: "single type per file",
                message: structureSingleTypePerFileMessage
            )
        )
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDecl(node, at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDecl(node, at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDecl(node, at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDecl(node, at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDecl(node, at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    // `#if` / `#elseif` / `#else` clauses are mutually exclusive at
    // compile time — the common cross-platform-conditional shape
    // declares the SAME logical top-level type once per branch (e.g.
    // a `#if os(Linux) struct Foo {} #else struct Foo {} #endif`
    // pair). The source-accurate view retains every branch, so the
    // default traversal would count each branch's declaration
    // separately and false-positive on platform-conditional code.
    // Walk only the first clause; skip the rest entirely.
    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        if let firstClause = node.clauses.first {
            walk(firstClause)
        }
        return .skipChildren
    }
}
