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

/// Wave 3 (mechanization-program) — platform identity checks MUST use
/// `#if os(...)`, not `#if canImport(...)`.
///
/// Citation: `[PATTERN-004a]` (platform skill — source-level platform
/// conditionals).
extension Lint.Rule {
    public static let `canimport conditional` = Lint.Rule(
        id: "canimport conditional",
        default: .warning,
        controls: [
            .init(
                id: "canimport conditional platform module",
                source: "#if canImport(Linux_Kernel)\nimport Linux_Kernel\n#endif",
                path: "Sources/Platform Core/LinuxAvailability.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "canimport conditional c library availability",
                source: "#if canImport(Glibc)\nimport Glibc\n#endif",
                path: "Sources/Platform Core/LibcAvailability.swift",
                expectation: .clean
            ),
            .init(
                id: "canimport conditional os boundary",
                source: "#if os(Linux)\nimport Glibc\n#endif",
                path: "Sources/Platform Core/OperatingSystem.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = PlatformPlatformConditionalVisitor(
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
internal let platformPlatformConditionalMessage: Swift.String =
    "[canimport conditional] [PATTERN-004a]: platform "
    + "identity check uses `#if canImport(...)` on a platform-prefixed "
    + "module — `canImport` evaluates against module resolution (varies "
    + "by build system); platform identity is what `#if os(...)` is "
    + "for (evaluates against the target triple). Reserve `canImport` "
    + "for module availability: optional feature modules (`SwiftUI`, "
    + "`Combine`, etc.) and the raw C-library trellis "
    + "(`#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)`), "
    + "which is genuine module availability — `os(Linux)` cannot "
    + "distinguish Glibc from Musl. Institute platform-prefixed modules "
    + "(`Darwin_Kernel_Standard` etc.) are the forbidden shape."

/// Raw C-library / system-SDK modules whose `canImport` IS module
/// availability, not platform identity — exempt (#16 Option C ledger,
/// Entry II.2 DECISION 2026-07-23). The canonical libc trellis
/// `#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)` cannot
/// be expressed with `os()` without losing the Musl arm (`os(Linux)` is
/// true for both Glibc and Musl), so the skill's own determinism table
/// (the platform compilation note [PATTERN-004a]) does not condemn it. Each
/// entry is an importable C-interop module shipped by a toolchain/SDK:
///
///   - `Darwin` — Apple libSystem clang module
///   - `Glibc` / `Musl` / `Bionic` — Linux/Android libc modules
///   - `Android` — Android NDK module
///   - `WASILibc` — WASI libc module
///   - `WinSDK` / `ucrt` / `CRT` — Windows SDK / C runtime modules
///
/// Bare `Linux` / `Windows` are NOT importable modules — `canImport` on
/// them is always false and remains flagged (platform-identity confusion
/// plus a latent dead branch).
internal let platformPlatformConditionalCLibraryModules: Swift.Set<Swift.String> = [
    "Darwin",
    "Glibc",
    "Musl",
    "Bionic",
    "Android",
    "WASILibc",
    "WinSDK",
    "ucrt",
    "CRT",
]

/// Sourced from the pack's single platform-identity vocabulary
/// (`platformPlatformTokens` in `Lint.Rule.Platform.Shared.swift`) plus
/// the libc-module prefixes this rule also needs to recognise as a
/// platform-prefixed module root (`Glibc_Kernel`, `Musl_Kernel`, etc.).
/// Previously a hand-maintained copy of `platformPlatformTokens` that
/// forgot bare `Android` / `WASILibc` in this DETECTION set while they
/// were remembered in the C-library-modules EXEMPTION set above — the
/// rule was strictly weaker on exactly the platforms most likely to
/// carry sloppy `canImport` gating, in direct conflict with the cross-
/// platform mandate. Routing through the shared vocabulary closes that
/// drift permanently: a platform added to `platformPlatformTokens` is
/// automatically covered here too. Note
/// `platformPlatformConditionalIsPlatformModuleName` still checks the
/// C-library-modules exemption FIRST, so the bare module names
/// themselves (`Android`, `WASILibc`) remain exempt — only the
/// `<Prefix>_`-suffixed platform-identity shape is detected.
internal let platformPlatformConditionalPlatformPrefixes: Swift.Set<Swift.String> =
    platformPlatformTokens.union(["Glibc", "Musl", "Bionic", "WinSDK"])

internal func platformPlatformConditionalIsPlatformModuleName(_ name: Swift.String) -> Swift.Bool {
    // Exempt the raw C-library / system-SDK modules (#16 Entry II.2):
    // gating on their importability is the sanctioned libc trellis.
    if platformPlatformConditionalCLibraryModules.contains(name) { return false }
    if platformPlatformConditionalPlatformPrefixes.contains(name) { return true }
    for prefix in platformPlatformConditionalPlatformPrefixes {
        if name.hasPrefix("\(prefix)_") { return true }
    }
    return false
}

internal final class PlatformPlatformConditionalVisitor: SyntaxVisitor {
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

    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        guard let condition = node.condition else { return .visitChildren }
        checkCondition(condition)
        return .visitChildren
    }

    /// Resolves a `canImport(...)` argument's root base identifier: a
    /// bare `Darwin_Kernel` is a `DeclReferenceExprSyntax`; a qualified
    /// `Darwin.POSIX` is a `MemberTypeSyntax`-shaped `MemberAccessExprSyntax`
    /// whose leftmost base is the module actually being imported (#21
    /// defect 13) — the exemption/detection vocabulary must be checked
    /// against that root, not the leaf.
    private func rootModuleIdentifier(of expression: ExprSyntax) -> TokenSyntax? {
        if let identifier = expression.as(DeclReferenceExprSyntax.self) {
            return identifier.baseName
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return nil }
            return rootModuleIdentifier(of: base)
        }
        return nil
    }

    private func checkCondition(_ expression: ExprSyntax) {
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
                callee.baseName.text == "canImport"
            {
                if let argument = call.arguments.first,
                    let root = rootModuleIdentifier(of: argument.expression)
                {
                    if platformPlatformConditionalIsPlatformModuleName(root.text) {
                        let position = root.positionAfterSkippingLeadingTrivia
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
                                identifier: "canimport conditional",
                                message: platformPlatformConditionalMessage
                            )
                        )
                    }
                }
            }
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            for element in sequence.elements {
                checkCondition(element)
            }
        }
        // Defensive: `#if` conditions arrive unfolded from the parser, so
        // this branch is not reachable from `visit(_: IfConfigClauseSyntax)`
        // today. Kept per the pack's established dual-shape convention for
        // fold/unfold differences (20a77b9's `Naming.BoolParameter`
        // precedent) rather than deleted — no fixture, since a test would
        // have to hand-construct the folded shape and would assert nothing
        // about the rule.
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            checkCondition(infix.leftOperand)
            checkCondition(infix.rightOperand)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            checkCondition(prefix.expression)
        }
    }
}
