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

/// An `@_exported import` outside a target's single umbrella `exports.swift`
/// re-exports a dependency edge from an ordinary source file, where no
/// import-based measurement looks for it. Citation: `[ARCH-FOUND-001]`
/// (TX-A2, swift-compositions/swift-linter#44).
///
/// The derived architecture model (Workspace.Architecture, TX-A1) measures
/// dependency edges from imports. A re-export makes the re-exporting module's
/// consumers see the re-exported module WITHOUT importing it, so every
/// scattered `@_exported import` widens the gap between the measured graph
/// and the real one — both directions: a dependency can be present but
/// unmeasured, or measured as absent while still reachable. Concentrating
/// re-exports in one conventional umbrella file per target keeps that gap
/// enumerable: a measurement that must reason about re-exports has exactly
/// one file name to consult.
///
/// This rule is AST-local. It does not decide whether a re-export is
/// architecturally justified — that is the derived model's judgment (TX-A4
/// binds enforcement). It only pins re-exports to the place where they can
/// be seen.
extension Lint.Rule {
    public static let `architecture import boundary` = Lint.Rule(
        id: "architecture import boundary",
        default: .warning,
        controls: [
            .init(
                id: "architecture import boundary ordinary reexport",
                source: "@_exported import Binary",
                path: "Sources/Architecture Core/OrdinaryReexport.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "architecture import boundary plain import",
                source: "public import Binary",
                path: "Sources/Architecture Core/PlainImport.swift",
                expectation: .clean
            ),
            .init(
                id: "architecture import boundary umbrella exemption",
                source: "@_exported public import Binary",
                path: "Sources/Architecture Core/exports.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            // Exempt per [RULE-EXEMPT-12] (path-scoped file): the umbrella
            // `exports.swift` IS the sanctioned re-export surface — the same
            // house convention `Lint.Rule.Foundation.Import`'s soundness suite
            // names. Filename-keyed, not directory-keyed: an umbrella sits at
            // a target root at any depth.
            guard !architectureImportBoundaryIsUmbrellaExportsFile(source.file.filePath) else {
                return []
            }
            // Exempt per [RULE-EXEMPT-12] (path-scoped target): test, experiment
            // and example sources ship to no consumer, so a re-export there
            // distorts no measured consumer edge. Segment set matches
            // `Lint.Rule.Foundation.Import` exactly.
            guard !architectureImportBoundaryIsOutsideMainTarget(source.file.filePath) else {
                return []
            }
            let visitor = ArchitectureImportBoundaryVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

/// The single sanctioned umbrella filename. Exact whole-filename match: a
/// file merely ending in `…exports.swift` (`ReExports.swift`,
/// `Model.exports.swift`) is NOT the umbrella and still fires.
private let architectureImportBoundaryUmbrellaFilename: Swift.String = "exports.swift"

/// Returns true when `filePath`'s trailing filename is exactly the umbrella
/// `exports.swift`.
private func architectureImportBoundaryIsUmbrellaExportsFile(
    _ filePath: Swift.String
) -> Swift.Bool {
    guard let filename = filePath.split(separator: "/", omittingEmptySubsequences: true).last
    else { return false }
    return filename == architectureImportBoundaryUmbrellaFilename
}

/// Root directory names outside a package's main targets. Matches the
/// segment set of `Lint.Rule.Foundation.Import`,
/// `Lint.Rule.Structure.SingleTypePerFile` and
/// `Lint.Rule.Memory.PointerArithmetic`; the rules should agree on what
/// "not a main target" means.
private let architectureImportBoundaryNonMainTargetRoots: [Swift.String] = [
    "Tests",
    "Experiments",
    "Examples",
]

/// Returns true when `filePath` sits under a non-main-target root — i.e.
/// some whole directory segment is `Tests`, `Experiments` or `Examples`.
/// Whole segments only: `Sources/TestKit/…` still fires.
private func architectureImportBoundaryIsOutsideMainTarget(
    _ filePath: Swift.String
) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains { component in
        architectureImportBoundaryNonMainTargetRoots.contains(Swift.String(component))
    }
}

private let architectureImportBoundaryMessage: Swift.String =
    "[architecture import boundary] [ARCH-FOUND-001]: `@_exported import` "
    + "re-exports a dependency edge that import-based architecture measurement "
    + "cannot see from consumers. Re-exports belong in the target's single "
    + "umbrella `exports.swift`, never in ordinary source files. If the module "
    + "is needed here, import it plainly; if the target's public surface should "
    + "re-export it, move the `@_exported import` to `exports.swift`."

internal final class ArchitectureImportBoundaryVisitor: SyntaxVisitor {
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

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // Structural, not textual: the `@_exported` attribute node itself, so
        // `@_exported public import X`, comment-interleaved trivia, and any
        // spacing all match — the shapes a regex loses.
        let isExported = node.attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.trimmedDescription == "_exported"
        }
        guard isExported else { return .visitChildren }
        let location = converter.location(for: node.path.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "architecture import boundary",
                message: architectureImportBoundaryMessage
            )
        )
        return .visitChildren
    }
}
