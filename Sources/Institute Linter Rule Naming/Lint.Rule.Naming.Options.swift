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

/// `OptionSet` type with a `Flags` suffix — the institute uses `.Options`.
extension Lint.Rule {
    public static let `property named flags` = Lint.Rule(
        id: "property named flags",
        default: .warning,
        controls: [
            .init(
                id: "property named flags option set",
                source: "struct OpenFlags: OptionSet { let rawValue: Int }",
                path: "Sources/Naming Core/FlagsOptionSet.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "property named flags options convention",
                source: "struct OpenOptions: OptionSet { let rawValue: Int }",
                path: "Sources/Naming Core/OptionsOptionSet.swift",
                expectation: .clean
            ),
            .init(
                id: "property named flags non option set",
                source: "struct DebugFlags { var verbose: Bool }",
                path: "Sources/Naming Core/NonOptionSet.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = NamingOptionsVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let namingOptionsMessage: Swift.String =
    "[property named flags] [API-NAME-011]: an `OptionSet` type named with "
    + "the `Flags` suffix uses C-speak. The institute convention is `.Options` "
    + "(e.g., `File.Open.Options`, `Walk.Options`)."

internal final class NamingOptionsVisitor: SyntaxVisitor {
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
        let name = node.name.text
        // Bare `Flags` is the exact C-speak this rule targets — `struct Flags:
        // OptionSet` is not exempt merely because it lacks a further prefix.
        guard name.hasSuffix("Flags") else { return .visitChildren }
        guard let inheritance = node.inheritanceClause,
            namingOptionsConformsToOptionSet(inheritance)
        else { return .visitChildren }
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
                identifier: "property named flags",
                message: namingOptionsMessage
            )
        )
        return .visitChildren
    }
}

private func namingOptionsConformsToOptionSet(_ clause: InheritanceClauseSyntax) -> Swift.Bool {
    for entry in clause.inheritedTypes {
        if let identifier = entry.type.as(IdentifierTypeSyntax.self),
            identifier.name.text == "OptionSet"
        {
            return true
        }
        if let member = entry.type.as(MemberTypeSyntax.self),
            member.name.text == "OptionSet",
            let base = member.baseType.as(IdentifierTypeSyntax.self),
            base.name.text == "Swift"
        {
            return true
        }
    }
    return false
}
