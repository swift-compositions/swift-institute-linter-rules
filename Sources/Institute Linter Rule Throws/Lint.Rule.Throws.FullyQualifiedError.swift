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

/// Nested `Error` types in typed-throws positions use their full owner path.
///
/// A bare `throws(Error)` is valid Swift, but it hides the error's ownership
/// from the signature itself. The canonical spelling keeps that context local:
/// `throws(Algebra.Field<Element>.Error)`. This applies equally to declaration
/// signatures, closure function types, closure signatures, and `do throws`.
extension Lint.Rule {
    public static let `fully qualified error in typed throws` = Lint.Rule(
        id: "fully qualified error in typed throws",
        default: .warning,
        controls: [
            .init(
                id: "fully qualified error bare",
                source: "func read() throws(Error) {}",
                path: "Sources/Throws Consumer/BareError.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "fully qualified error canonical",
                source: "func read() throws(Read.Error) {}",
                path: "Sources/Throws Consumer/QualifiedError.swift",
                expectation: .clean
            ),
            .init(
                id: "fully qualified error distinct nominal",
                source: "func read() throws(ReadError) {}",
                path: "Sources/Throws Consumer/NominalError.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ThrowsFullyQualifiedErrorVisitor(
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
internal let throwsFullyQualifiedErrorMessage: Swift.String =
    "[fully qualified error in typed throws]: bare `throws(Error)` loses the "
    + "owning domain from the local signature; spell the complete nested type "
    + "path (for example `throws(Algebra.Field<Element>.Error)`)."

internal final class ThrowsFullyQualifiedErrorVisitor: SyntaxVisitor {
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

    override func visit(_ node: ThrowsClauseSyntax) -> SyntaxVisitorContinueKind {
        guard let type = node.type,
            let identifier = type.as(IdentifierTypeSyntax.self),
            identifier.name.text == "Error"
        else { return .visitChildren }

        let location = converter.location(for: type.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "fully qualified error in typed throws",
                message: throwsFullyQualifiedErrorMessage
            )
        )
        return .visitChildren
    }
}
