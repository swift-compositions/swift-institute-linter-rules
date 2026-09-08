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

/// No package's main target imports the Foundation module family, at any of
/// the five layers. Citation: `[ARCH-LAYER-007]`; `[PRIM-FOUND-001]` is the
/// Layer-1 specialization of the same discipline.
///
/// The family is `Foundation`, `FoundationEssentials`, `FoundationNetworking`
/// and `FoundationXML`. `FoundationNetworking` matters disproportionately: it
/// is where `URLSession` lives on Linux, so omitting it leaves the rule blind
/// on precisely the axis it exists to guard.
extension Lint.Rule {
    public static let `foundation import` = Lint.Rule(
        id: "foundation import",
        default: .warning,
        controls: [
            .init(
                id: "foundation import main target",
                source: "import Foundation",
                path: "Sources/Foundation Core/FoundationImport.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "foundation import unrelated module",
                source: "import Binary",
                path: "Sources/Foundation Core/BinaryPrimitivesImport.swift",
                expectation: .clean
            ),
            .init(
                id: "foundation import integration target",
                source: "import Foundation",
                path: "Sources/Foundation Foundation Integration/FoundationImport.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            // Exempt per [RULE-EXEMPT-12] (path-scoped target): the dedicated,
            // opt-in `* Foundation Integration` subtarget is the sanctioned
            // Foundation boundary consumers opt into per `[PRIM-FOUND-001]`,
            // named by this rule's own message. A file whose path carries a
            // `… Foundation Integration/` directory segment IS that boundary, so
            // its Foundation import is legitimate by construction. Every core
            // target, at every layer, is still walked and still fires.
            guard !foundationImportIsInsideFoundationIntegrationTarget(source.file.filePath) else {
                return []
            }
            // Exempt per [RULE-EXEMPT-12] (path-scoped target): `[ARCH-LAYER-007]`
            // governs a package's MAIN targets. Test, experiment and example
            // sources ship to no consumer and impose Foundation on nothing, so
            // firing there was over-reporting — and noise that authors are told
            // to ignore is how a real finding gets ignored too. Mirrors the
            // scope exclusion in `Lint.Rule.Structure.SingleTypePerFile` and
            // `Lint.Rule.Memory.PointerArithmetic`, which use this same segment
            // set; kept as a separate guard from the FI carve-out above because
            // it is a different sanctioned category with a different rationale.
            guard !foundationImportIsOutsideMainTarget(source.file.filePath) else {
                return []
            }
            // Exempt per [RULE-EXEMPT-12] (path-scoped target): a package manifest
            // is not a target at all. SwiftPM compiles `Package.swift` in its own
            // manifest sandbox and ships it to no consumer, so a manifest's
            // `import Foundation` cannot impose Foundation on anyone — which is
            // the harm `[ARCH-LAYER-007]` exists to prevent. Keyed on the FILENAME,
            // unlike the two directory-segment gates above; that difference is
            // deliberate, because the manifest is identified by its name and can
            // sit at any package root, including a nested package's.
            guard !foundationImportIsPackageManifest(source.file.filePath) else {
                return []
            }
            let visitor = FoundationImportVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

/// The directory-name suffix identifying a dedicated, opt-in Foundation
/// Integration subtarget (`[PRIM-FOUND-001]`). The leading space mandates a
/// non-empty brand token, so real targets — `JSON Foundation Integration`,
/// `Structured Queries Foundation Integration` — match while a
/// core target merely NAMED with `Foundation` in it (`HTML Foundation`) does
/// not.
private let foundationIntegrationTargetSuffix: Swift.String = " Foundation Integration"

/// Returns true when `filePath` lives inside a `* Foundation Integration`
/// subtarget — i.e. some *directory* segment of the path ends in
/// ` Foundation Integration`. Only directory segments qualify: the trailing
/// filename is dropped, so a source file that merely happens to end in
/// `… Foundation Integration.swift` inside a core target is NOT exempted.
private func foundationImportIsInsideFoundationIntegrationTarget(
    _ filePath: Swift.String
) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains { $0.hasSuffix(foundationIntegrationTargetSuffix) }
}

/// Root directory names whose contents are, by SwiftPM and institute
/// convention, not part of a package's main targets. `[ARCH-LAYER-007]`
/// governs main targets, so these are outside its scope.
///
/// The set matches `Lint.Rule.Structure.SingleTypePerFile` and
/// `Lint.Rule.Memory.PointerArithmetic` exactly; the three rules should
/// agree on what "not a main target" means.
private let foundationImportNonMainTargetRoots: [Swift.String] = [
    "Tests",
    "Experiments",
    "Examples",
]

/// Returns true when `filePath` sits under a non-main-target root — i.e.
/// some whole *directory* segment is `Tests`, `Experiments` or `Examples`.
///
/// Whole segments only, so a main-target file is not exempted by a
/// coincidental substring: `Sources/TestKit/…` and `Sources/Examples.swift`
/// both still fire. A nested `Sources/Foo/Tests/…` does match, which is the
/// established behaviour of the two sibling rules above rather than a
/// decision taken here.
private func foundationImportIsOutsideMainTarget(_ filePath: Swift.String) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains { component in
        foundationImportNonMainTargetRoots.contains(Swift.String(component))
    }
}

/// Returns true when `filePath` names a SwiftPM package manifest — `Package.swift`
/// or a version-specific `Package@swift-<version>.swift`.
///
/// Keyed on the trailing filename rather than a directory segment, because a
/// manifest is identified by its name and sits at a package root — including
/// the root of a *nested* package, which a root-relative test would miss.
/// The match is exact on the whole component, so an ordinary source file
/// merely mentioning the word (`PackageInfo.swift`, `MyPackage.swift`, or any
/// file inside a directory named `Package`) still fires.
private func foundationImportIsPackageManifest(_ filePath: Swift.String) -> Swift.Bool {
    guard let filename = filePath.split(separator: "/", omittingEmptySubsequences: true).last
    else { return false }
    if filename == "Package.swift" { return true }
    return filename.hasPrefix("Package@swift-") && filename.hasSuffix(".swift")
}

// MARK: - Recorded scope decisions
//
// The contexts below were enumerated against the SwiftPM target model
// (`regular`, `executable`, `test`, `system`, `binary`, `plugin`, `macro`,
// plus the `Snippets/` directory convention) on 2026-07-25, after this rule
// had over-reported in three non-main-target contexts discovered one incident
// at a time. They are recorded here so a future instance is a known change
// rather than a rediscovery.
//
// - `executable`: **exempt as policy, deliberately NOT implemented.** An
//   executable ships as a binary and imposes Foundation on no library
//   consumer, so it does not commit the harm this rule prevents. It cannot be
//   implemented here: executable targets live in `Sources/<Name>/` exactly
//   like library targets, so no path predicate can distinguish them. Doing so
//   needs manifest awareness in the engine — a different change to a
//   different component. 88 institute manifests declare executables; how many
//   of those targets actually import Foundation is unmeasured, and that
//   sizing should precede any engine work.
//
// - `plugin`, `macro`, `snippet`, `system`, `binary`: **zero instances across
//   the institute fleet** (2,224 manifests, 2026-07-25). Deliberately not
//   exempted — a both-direction fixture for a context with no real instance
//   means inventing the shape being exempted. Detection approach when a first
//   instance appears: `plugin` and `snippet` are path-distinguishable by the
//   SwiftPM `Plugins/` and `Snippets/` directory conventions and belong in
//   `foundationImportNonMainTargetRoots`; `macro` is NOT path-distinguishable
//   and shares the executable problem above; `system` and `binary` carry no
//   Swift sources, so nothing reaches this rule.
//
// ⚠️ The general limit, worth reading before adding a fourth gate: **this
// class is not closed under path.** Three contexts happened to be
// path-distinguishable and were fixed; `executable` and `macro` are not, and
// no further enumeration changes that.

@usableFromInline
internal let foundationImportMessage: Swift.String =
    "[foundation import] [ARCH-LAYER-007]: no package's main target may import "
    + "the Foundation module family (`Foundation`, `FoundationEssentials`, "
    + "`FoundationNetworking`, `FoundationXML`) — at ANY of the five layers, not "
    + "just primitives. Use institute primitives (`Time`, "
    + "`Binary`, etc.) instead. Foundation-adjacent interop belongs in "
    + "a separately-declared `* Foundation Integration` subtarget that consumers "
    + "opt into, never the main target. (`[PRIM-FOUND-001]` is the Layer-1 "
    + "specialization of this rule; it is not a primitives-only rule.)"

internal final class FoundationImportVisitor: SyntaxVisitor {
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
        let pathText = node.path.trimmedDescription
        guard foundationImportIsFoundationModule(pathText) else {
            return .visitChildren
        }
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
                identifier: "foundation import",
                message: foundationImportMessage
            )
        )
        return .visitChildren
    }
}

/// The Foundation module family this rule flags.
///
/// `FoundationNetworking` and `FoundationXML` are the corelibs-Foundation
/// modules on Linux; importing either pulls in Foundation just as surely as
/// importing `Foundation` itself does.
private let foundationModuleFamily: Swift.Set<Swift.String> = [
    "Foundation",
    "FoundationEssentials",
    "FoundationNetworking",
    "FoundationXML",
]

/// Returns true if `pathText` names a module in the Foundation family.
/// Submodule imports (`Foundation.NSURL`) are also caught — any path whose
/// FIRST component is a family member pulls in the framework and counts as a
/// violation. Modules with a family name in a NON-leading position
/// (`HTML_Foundation`, `Server_Foundation`) are deliberately not flagged.
private func foundationImportIsFoundationModule(_ pathText: Swift.String) -> Swift.Bool {
    let firstComponent = pathText.split(separator: ".").first.map(Swift.String.init) ?? pathText
    return foundationModuleFamily.contains(firstComponent)
}
