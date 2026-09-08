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

/// Top-level `@Suite struct X` declarations MUST contain all three
/// canonical sub-suites as nested `@Suite struct` members:
/// `Unit`, `` `Edge Case` ``, `Integration`. Citation: `[TEST-005]`.
///
/// Performance benchmarking is OUT of the test-framework scope — the
/// institute performs performance work in separate benchmark packages
/// per the `benchmark` skill. The `Performance` sub-suite that earlier
/// versions of this rule required is therefore vestigial and was
/// dropped 2026-05-15. A `Performance` sub-suite may still exist and
/// passes the rule (3 required + arbitrary extras is fine), but it's
/// no longer required.
///
/// A `@Suite struct` declared directly inside a top-level `extension`
/// (the house suite idiom, e.g. `extension Lint.Rule { @Suite struct
/// \`X Tests\` { ... } }`) IS in scope — the extension is the
/// declaration site, not a reopening of an unrelated namespace. Only a
/// `@Suite struct` nested inside another nominal type (struct, class,
/// enum, actor) is out of scope; that nesting is genuine, not idiomatic.
extension Lint.Rule {
    public static let `suite categories` = Lint.Rule(
        id: "suite categories",
        default: .warning,
        controls: [
            .init(
                id: "suite categories missing",
                source: "@Suite struct Example {}",
                path: "Sources/Framework Core/MissingCategories.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "suite categories canonical",
                source: "@Suite struct Example { @Suite struct Unit {}; @Suite struct `Edge Case` {}; @Suite struct Integration {} }",
                path: "Sources/Framework Core/CanonicalCategories.swift",
                expectation: .clean
            ),
            .init(
                id: "suite categories nested nominal",
                source: "enum Host { @Suite struct Example {} }",
                path: "Sources/Framework Core/NestedNominal.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = FrameworkSuiteCategoriesVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        },
        repair: { source in
            guard let contents = frameworkSuiteCategoriesFixed(source) else { return .unchanged }
            return .edits([.rewrite(path: source.path, contents: contents)])
        }
    )
}

@usableFromInline
internal let frameworkSuiteCategoriesMessage: Swift.String =
    "[suite categories] [TEST-005]: top-level `@Suite struct` MUST contain "
    + "all three canonical sub-suites declared via nested "
    + "`@Suite struct (Unit | \\`Edge Case\\` | Integration)`. "
    + "Fixed categories enable cross-package grep-ability per `[TEST-005]`. "
    + "Performance benchmarking is OUT of the test-framework scope — done "
    + "via separate benchmark packages per the `benchmark` skill. A "
    + "`Performance` sub-suite may still exist (rule won't fire on extras) "
    + "but is no longer required."

internal final class FrameworkSuiteCategoriesVisitor: SyntaxVisitor {
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
        guard suiteCategoriesHasSuiteAttribute(node.attributes) else {
            return .visitChildren
        }
        guard suiteCategoriesIsTopLevel(Syntax(node)) else {
            return .visitChildren
        }
        let missing = suiteCategoriesMissingFromBody(node.memberBlock)
        if !missing.isEmpty {
            emit(at: node.name.positionAfterSkippingLeadingTrivia, missing: missing)
        }
        return .visitChildren
    }

    private func emit(at position: AbsolutePosition, missing: [Swift.String]) {
        let location = converter.location(for: position)
        let missingList = missing.joined(separator: ", ")
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "suite categories",
                message: frameworkSuiteCategoriesMessage + " Missing: \(missingList)."
            )
        )
    }
}

/// Returns true if `attrs` contains a `@Suite` attribute (with or without
/// trait arguments), bare or qualified (`@Testing.Suite`).
///
/// Suffix-based, matching the `.Suite`-suffix handling this package's other
/// predicates already use (`Lint.Rule.Structure.MinimalTypeBody`'s
/// extension-pattern-attribute check, `Lint.Rule.Throws.Untyped`'s leaf
/// match) — see swift-compositions/swift-institute-linter-rules#45. A bare
/// name that merely ENDS IN "Suite" without the separating dot (`@BarSuite`)
/// does not match: `"BarSuite".hasSuffix(".Suite")` is false because there
/// is no dot before the suffix.
internal func suiteCategoriesHasSuiteAttribute(_ attrs: AttributeListSyntax) -> Swift.Bool {
    for attr in attrs {
        guard case .attribute(let a) = attr else { continue }
        let name = a.attributeName.trimmedDescription
        if name == "Suite" || name.hasSuffix(".Suite") {
            return true
        }
    }
    return false
}

/// Returns true if `node` is declared at source-file scope, treating
/// `ExtensionDeclSyntax` ancestors as transparent.
///
/// The house suite idiom declares every suite as
/// `extension Lint.Rule { @Suite struct \`X Tests\` { … } }` — the
/// extension *is* the declaration site, not an unrelated namespace being
/// extended. An `ExtensionDeclSyntax` ancestor is therefore skipped
/// rather than disqualifying; any other struct/class/enum/actor
/// ancestor still disqualifies (a suite nested inside another type is
/// genuinely nested, not top-level).
internal func suiteCategoriesIsTopLevel(_ node: Syntax) -> Swift.Bool {
    var current = node.parent
    while let parent = current {
        if parent.is(ExtensionDeclSyntax.self) {
            current = parent.parent
            continue
        }
        if parent.is(StructDeclSyntax.self)
            || parent.is(EnumDeclSyntax.self)
            || parent.is(ClassDeclSyntax.self)
            || parent.is(ActorDeclSyntax.self)
        {
            return false
        }
        current = parent.parent
    }
    return true
}

private let suiteCategoriesCanonical: [Swift.String] = [
    "Unit", "`Edge Case`", "Integration",
]

/// Returns the list of canonical category names that are NOT declared as
/// nested `@Suite struct` members within `memberBlock`. Names are
/// returned in canonical order.
internal func suiteCategoriesMissingFromBody(_ memberBlock: MemberBlockSyntax) -> [Swift.String] {
    var declared = Set<Swift.String>()
    for member in memberBlock.members {
        guard let structDecl = member.decl.as(StructDeclSyntax.self) else { continue }
        guard suiteCategoriesHasSuiteAttribute(structDecl.attributes) else { continue }
        let raw = structDecl.name.text
        // Backticked identifiers carry the backticks in `.text`; normalize.
        let stripped = Lint.Syntax.Identifier.unescaped(raw)
        switch stripped {
        case "Unit": declared.insert("Unit")
        case "Edge Case": declared.insert("`Edge Case`")
        case "Integration": declared.insert("Integration")
        default: continue
        }
    }
    return suiteCategoriesCanonical.filter { !declared.contains($0) }
}
