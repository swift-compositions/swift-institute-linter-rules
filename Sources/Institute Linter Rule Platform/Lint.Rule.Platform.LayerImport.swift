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

/// Non-platform-stack sources MUST NOT import platform-specific L2-spec or
/// L3-policy modules directly — consumers `import Kernel`, not
/// `import Darwin_Kernel_Standard` / `import POSIX_Kernel` etc.
/// Citation: `[PLAT-ARCH-008]`.
///
/// Mirrors `validate-layer-deps.py check_plat_arch_008` (swift-institute/
/// .github, Wave 2 mechanization 2026-05-11). Parity note, recorded per
/// swift-institute/.github#358 F9: the Python classifies a whole PACKAGE as
/// platform-stack via (a) an explicit repo-name registry and (b) a
/// `Package.swift` dependency signal on any L2-spec/L3-policy package
/// ([PLAT-ARCH-021] derivation). A per-file lint rule has no manifest in
/// scope, so (a) is mirrored as a path-segment predicate against the same
/// registry, and (b) is NOT mirrorable per-file. Fail-closed: a
/// dep-signal-classified package whose checkout path does not carry a
/// registry name still fires and must suppress or disable the rule locally.
extension Lint.Rule {
    public static let `platform layer import` = Lint.Rule(
        id: "platform layer import",
        default: .warning,
        controls: [
            .init(
                id: "platform layer import direct policy module",
                source: "import POSIX_Kernel",
                path: "Sources/Consumer Core/DirectPolicyImport.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "platform layer import unifier surface",
                source: "import Kernel",
                path: "Sources/Consumer Core/KernelImport.swift",
                expectation: .clean
            ),
            .init(
                id: "platform layer import test boundary",
                source: "import POSIX_Kernel",
                path: "Tests/Consumer Tests/PolicyFixture.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            // Exempt per [RULE-EXEMPT-12] (path-scoped package): the platform
            // stack itself — L1 platform-aware primitives, L2 spec, L3-policy,
            // L3-unifier and the L3-domain `swift-file-system` — exists
            // precisely so the rest of the ecosystem doesn't need these
            // imports. Mirrors the Python's PLATFORM_STACK registry, keyed on
            // a whole path segment equal to a registry package name.
            guard !platformLayerImportIsInsidePlatformStackPackage(source.file.filePath) else {
                return []
            }
            // Exempt: the Python scans `Sources/` only, so test, experiment
            // and example trees, package manifests, and hidden directories are
            // never inspected. Mirrored with the pack's established path
            // gates (segment set matches `Lint.Rule.Foundation.Import`).
            guard !platformLayerImportIsOutsideMainTarget(source.file.filePath) else {
                return []
            }
            guard !platformLayerImportIsPackageManifest(source.file.filePath) else {
                return []
            }
            guard !platformLayerImportIsInsideHiddenDirectory(source.file.filePath) else {
                return []
            }
            let visitor = PlatformLayerImportVisitor(
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
internal let platformLayerImportMessage: Swift.String =
    "[platform layer import] [PLAT-ARCH-008]: non-platform-stack source "
    + "imports a platform-specific L2-spec or L3-policy module directly. "
    + "Consumers MUST import the L3-unifier surface (`import Kernel`, "
    + "`import IO`, etc.), never `Darwin_Kernel_Standard`, "
    + "`Linux_Kernel_Standard`, `Windows_32_Core`, `ISO_9945_Core`, "
    + "`Darwin_Kernel`, `Linux_Kernel`, `Windows_Kernel` or `POSIX_Kernel`. "
    + "The platform stack (L1 platform primitives, L2 spec, L3-policy, "
    + "L3-unifier, `swift-file-system`) exists precisely so the rest of the "
    + "ecosystem doesn't need these imports."

/// The platform-specific module names consumers MUST NOT directly import
/// per `[PLAT-ARCH-008]`, mapped to the canonical owning package for the
/// diagnostic. Mirrors `PLATFORM_IMPORT_FORBIDDEN` in
/// `validate-layer-deps.py` exactly.
internal let platformLayerImportForbiddenModules: [Swift.String: Swift.String] = [
    // L2 platform-spec modules
    "Darwin_Kernel_Standard": "swift-darwin-standard",
    "Linux_Kernel_Standard": "swift-linux-standard",
    "Windows_32_Core": "swift-windows-32",
    "ISO_9945_Core": "swift-iso-9945",
    // L3-policy modules
    "Darwin_Kernel": "swift-darwin",
    "Linux_Kernel": "swift-linux",
    "Windows_Kernel": "swift-windows",
    "POSIX_Kernel": "swift-posix",
]

/// The platform-stack package registry — the union of the Python's
/// `L1_PLATFORM_PRIMITIVES | L2_SPEC | L3_POLICY | L3_UNIFIER | L3_DOMAIN`
/// sets, verbatim. A file whose path carries one of these names as a whole
/// directory segment belongs to the platform stack and is exempt.
internal let platformLayerImportPlatformStackPackages: Swift.Set<Swift.String> = [
    // L1 platform-aware primitives
    "swift-kernel",
    "swift-cpu",
    "swift-darwin",
    "swift-linux",
    "swift-windows",
    // L2 spec
    "swift-iso-9945",
    "swift-darwin-standard",
    "swift-linux-standard",
    "swift-windows-32",
    "swift-windows-standard",  // historical name; renamed to swift-windows-32 2026-04-30
    // L3-policy
    "swift-posix",
    "swift-darwin",
    "swift-linux",
    "swift-windows",
    // L3-unifier
    "swift-kernel",
    "swift-strings",
    "swift-paths",
    "swift-ascii",
    "swift-systems",
    "swift-io",
    "swift-threads",
    "swift-environment",
    // L3-domain
    "swift-file-system",
]

/// Returns true when some whole DIRECTORY segment of `filePath` names a
/// platform-stack package. Whole segments only, so a look-alike
/// (`swift-kernel-tools`) is not exempted; the trailing filename is
/// dropped, so a file merely NAMED after a stack package is not exempted.
private func platformLayerImportIsInsidePlatformStackPackage(
    _ filePath: Swift.String
) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains { component in
        platformLayerImportPlatformStackPackages.contains(Swift.String(component))
    }
}

/// Root directory names outside a package's main targets. Matches the
/// segment set in `Lint.Rule.Foundation.Import` (`Tests`, `Experiments`,
/// `Examples`); the Python only ever walks `Sources/`, so these trees are
/// out of its scope by construction.
private let platformLayerImportNonMainTargetRoots: [Swift.String] = [
    "Tests",
    "Experiments",
    "Examples",
]

private func platformLayerImportIsOutsideMainTarget(_ filePath: Swift.String) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count > 1 else { return false }
    return components.dropLast().contains { component in
        platformLayerImportNonMainTargetRoots.contains(Swift.String(component))
    }
}

/// A package manifest sits outside `Sources/` and is never scanned by the
/// Python; keyed on the filename per the pack's manifest-gate precedent.
private func platformLayerImportIsPackageManifest(_ filePath: Swift.String) -> Swift.Bool {
    guard let filename = filePath.split(separator: "/", omittingEmptySubsequences: true).last
    else { return false }
    if filename == "Package.swift" { return true }
    return filename.hasPrefix("Package@swift-") && filename.hasSuffix(".swift")
}

/// The Python skips any path with a hidden (`.`-prefixed) segment.
private func platformLayerImportIsInsideHiddenDirectory(_ filePath: Swift.String) -> Swift.Bool {
    let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
    return components.contains { $0.hasPrefix(".") }
}

/// Returns the owning package when `pathText`'s FIRST path component names
/// a forbidden module; submodule imports (`Darwin_Kernel.Something`) pull
/// in the module just as surely as the bare import does.
internal func platformLayerImportForbiddenPackage(_ pathText: Swift.String) -> Swift.String? {
    let firstComponent = pathText.split(separator: ".").first.map(Swift.String.init) ?? pathText
    return platformLayerImportForbiddenModules[firstComponent]
}

internal final class PlatformLayerImportVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    /// The Python emits one finding per (module, file) pair; repeated imports
    /// of the same module in one file collapse to a single diagnostic.
    private var reportedModules: Swift.Set<Swift.String> = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let pathText = node.path.trimmedDescription
        let firstComponent = pathText.split(separator: ".").first.map(Swift.String.init) ?? pathText
        guard platformLayerImportForbiddenModules[firstComponent] != nil else {
            return .visitChildren
        }
        guard !reportedModules.contains(firstComponent) else {
            return .visitChildren
        }
        reportedModules.insert(firstComponent)
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
                identifier: "platform layer import",
                message: platformLayerImportMessage
            )
        )
        return .visitChildren
    }
}
