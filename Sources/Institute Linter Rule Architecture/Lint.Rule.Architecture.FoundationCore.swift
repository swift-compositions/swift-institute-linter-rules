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

/// Foundation-freedom governs *use* of Foundation types, not just the import
/// statement. Citation: `[ARCH-LAYER-007]`, `[ARCH-FOUND-001]` (TX-A2,
/// swift-compositions/swift-linter#44).
///
/// `Lint.Rule.Foundation.Import` owns the import form, and its own doctrine
/// records the residual blind spot: a Foundation type reached transitively —
/// through a dependency's umbrella re-export — is used without any local
/// `import Foundation` for the import rule to see. This rule closes the
/// AST-local half of that gap: it flags Foundation types *named in type
/// position* regardless of how the module became visible.
///
/// What is honestly decidable from one file's AST, and nothing more:
///
/// - a type position spelled with explicit `Foundation.` (or
///   `FoundationEssentials.` / `FoundationNetworking.` / `FoundationXML.`)
///   module qualification — unambiguous by construction;
/// - a type position or inheritance clause naming an `NS`-prefixed
///   CamelCase class (`NSObject`, `NSError`, `NSRegularExpression`, …) —
///   the `NS` prefix is Foundation/Objective-C's reserved namespace.
///
/// Unqualified short names (`Data`, `Date`, `URL`) are deliberately NOT
/// flagged: AST-locally they are indistinguishable from institute-owned
/// types of the same name, and a rule that guesses is a rule whose findings
/// get ignored. A zero from this rule is therefore evidence about qualified
/// and `NS`-prefixed use only; whole-graph Foundation reachability is the
/// derived model's to verify (TX-A1/TX-A4).
extension Lint.Rule {
    public static let `architecture foundation type` = Lint.Rule(
        id: "architecture foundation type",
        default: .warning,
        controls: [
            .init(
                id: "architecture foundation type qualified use",
                source: "public var payload: Foundation.Data",
                path: "Sources/Architecture Core/QualifiedUse.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "architecture foundation type unqualified short name",
                source: "public var payload: Data",
                path: "Sources/Architecture Core/UnqualifiedShortName.swift",
                expectation: .clean
            ),
            .init(
                id: "architecture foundation type integration exemption",
                source: "public var payload: Foundation.Data",
                path: "Sources/Architecture Foundation Integration/QualifiedUse.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            // Exempt per [RULE-EXEMPT-12] (path-scoped target): the dedicated,
            // opt-in `* Foundation Integration` subtarget is the sanctioned
            // Foundation boundary. Same carve-out, same suffix predicate as
            // `Lint.Rule.Foundation.Import`.
            guard
                !architectureFoundationTypeIsInsideFoundationIntegrationTarget(source.file.filePath)
            else {
                return []
            }
            // Exempt per [RULE-EXEMPT-12] (path-scoped target): main targets
            // only — test, experiment and example sources impose Foundation on
            // no consumer. Segment set matches `Lint.Rule.Foundation.Import`.
            guard !architectureFoundationTypeIsOutsideMainTarget(source.file.filePath) else {
                return []
            }
            // Exempt per [RULE-EXEMPT-12] (filename): a package manifest runs in
            // SwiftPM's sandbox and ships to no consumer.
            guard !architectureFoundationTypeIsPackageManifest(source.file.filePath) else {
                return []
            }
            let visitor = ArchitectureFoundationTypeVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

/// The Foundation module family whose explicit qualification in type
/// position is flagged. Matches `Lint.Rule.Foundation.Import`'s family.
private let architectureFoundationTypeModuleFamily: [Swift.String] = [
    "Foundation",
    "FoundationEssentials",
    "FoundationNetworking",
    "FoundationXML",
]

/// Returns true when `name` is an `NS`-prefixed CamelCase class name —
/// `NS`, then an uppercase letter, then at least one lowercase letter
/// somewhere after the prefix. The lowercase requirement is the near-miss
/// gate: an all-caps identifier that merely starts with `NS` (`NSFW`) is
/// not a Foundation class spelling and does not fire.
private func architectureFoundationTypeIsFoundationClassName(
    _ name: Swift.String
) -> Swift.Bool {
    guard name.count > 2, name.hasPrefix("NS") else { return false }
    let remainder = name.dropFirst(2)
    guard let first = remainder.first, first.isUppercase else { return false }
    return remainder.contains { $0.isLowercase }
}

private let architectureFoundationTypeIntegrationTargetSuffix: Swift.String =
    " Foundation Integration"

private func architectureFoundationTypeIsInsideFoundationIntegrationTarget(
    _ filePath: Swift.String
) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains {
        $0.hasSuffix(architectureFoundationTypeIntegrationTargetSuffix)
    }
}

private let architectureFoundationTypeNonMainTargetRoots: [Swift.String] = [
    "Tests",
    "Experiments",
    "Examples",
]

private func architectureFoundationTypeIsOutsideMainTarget(
    _ filePath: Swift.String
) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains { component in
        architectureFoundationTypeNonMainTargetRoots.contains(Swift.String(component))
    }
}

private func architectureFoundationTypeIsPackageManifest(
    _ filePath: Swift.String
) -> Swift.Bool {
    guard let filename = filePath.split(separator: "/", omittingEmptySubsequences: true).last
    else { return false }
    if filename == "Package.swift" { return true }
    return filename.hasPrefix("Package@swift-") && filename.hasSuffix(".swift")
}

private let architectureFoundationTypeMessage: Swift.String =
    "[architecture foundation type] [ARCH-LAYER-007]: no package's main target "
    + "may USE Foundation types — Foundation-freedom governs use, not just the "
    + "import statement, and a transitively re-exported Foundation module makes "
    + "its types nameable without any local import for the import rule to see. "
    + "Use institute primitives instead; Foundation-adjacent interop belongs in "
    + "a separately-declared `* Foundation Integration` subtarget."

internal final class ArchitectureFoundationTypeVisitor: SyntaxVisitor {
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

    private func record(at position: AbsolutePosition) {
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
                identifier: "architecture foundation type",
                message: architectureFoundationTypeMessage
            )
        )
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        // Bare `NS`-prefixed class in type position: `let lock: NSLock`,
        // `class Model: NSObject` (inheritance clauses are type positions),
        // `func f() -> NSRange`.
        if architectureFoundationTypeIsFoundationClassName(node.name.text) {
            record(at: node.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        // Explicitly module-qualified type: `Foundation.Data`,
        // `FoundationNetworking.URLSession`. The base must be exactly the
        // module identifier — `My.Foundation.X` has a MemberType base, not an
        // IdentifierType base, and does not fire.
        if let base = node.baseType.as(IdentifierTypeSyntax.self),
            architectureFoundationTypeModuleFamily.contains(base.name.text)
        {
            record(at: node.positionAfterSkippingLeadingTrivia)
            // The base identifier will not be visited as a separate finding:
            // report the qualified use once, at the member type.
            return .skipChildren
        }
        return .visitChildren
    }
}
