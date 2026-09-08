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

/// Empty `Tag` sub-types nested inside another type — the surrounding
/// namespace MUST play the phantom role directly. Citation:
/// `[API-NAME-010a]`. Sibling of `Lint.Rule.Naming.Tag` per
/// `[API-NAME-010]`, which catches the suffix-form (`OrderTag`); this
/// rule catches the nested-sub-name form (`Order.Tag`).
extension Lint.Rule {
    public static let `nested tag` = Lint.Rule(
        id: "nested tag",
        default: .warning,
        controls: [
            .init(
                id: "nested tag empty nested",
                source: "enum Order { enum Tag {} }",
                path: "Sources/Naming Core/EmptyNestedTag.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "nested tag top level",
                source: "enum Tag {}",
                path: "Sources/Naming Core/TopLevelTag.swift",
                expectation: .clean
            ),
            .init(
                id: "nested tag data bearing",
                source: "enum Order { struct Tag { let value: Int } }",
                path: "Sources/Naming Core/DataBearingTag.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingNestedTagVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingNestedTagMessage: Swift.String =
    "[nested tag] [API-NAME-010a]: empty `Tag` sub-type nested inside another type "
    + "— the surrounding namespace MUST play the phantom role directly. "
    + "Use `Property<Order, T>` / `Tagged<Order, T>` instead of "
    + "`Property<Order.Tag, T>` / `Tagged<Order.Tag, T>`."

internal final class NamingNestedTagVisitor: SyntaxVisitor {
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

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == "Tag" else { return .visitChildren }
        guard !namingHasStoredInstanceProperty(node.memberBlock) else { return .visitChildren }
        guard nestedTagIsNested(Syntax(node)) else { return .visitChildren }
        emit(at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == "Tag" else { return .visitChildren }
        guard !namingHasEnumCase(node.memberBlock) else { return .visitChildren }
        guard nestedTagIsNested(Syntax(node)) else { return .visitChildren }
        emit(at: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    private func emit(at position: AbsolutePosition) {
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
                identifier: "nested tag",
                message: namingNestedTagMessage
            )
        )
    }
}

/// Returns true when `node` is nested inside a type-decl or extension
/// context — walks up the parent chain looking for any enclosing
/// `StructDeclSyntax` / `ClassDeclSyntax` / `EnumDeclSyntax` /
/// `ActorDeclSyntax` / `ExtensionDeclSyntax`.
private func nestedTagIsNested(_ node: Syntax) -> Swift.Bool {
    var current: Syntax? = node.parent
    while let candidate = current {
        if candidate.is(StructDeclSyntax.self) { return true }
        if candidate.is(ClassDeclSyntax.self) { return true }
        if candidate.is(EnumDeclSyntax.self) { return true }
        if candidate.is(ActorDeclSyntax.self) { return true }
        if candidate.is(ExtensionDeclSyntax.self) { return true }
        current = candidate.parent
    }
    return false
}
