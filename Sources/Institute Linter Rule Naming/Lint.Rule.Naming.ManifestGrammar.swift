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

/// Manifest naming grammar (swift-institute-linter-rules#65, principal
/// directive 2026-08-09): the SwiftPM manifest's own declared names
/// follow the ratified Nest.Name grammar.
///
/// The rule's surface is a package manifest (`Package.swift`, including
/// versioned `Package@swift-*.swift` variants and nested test
/// manifests). Three predicates, one rule:
///
/// 1. **Package slug**: the top-level `Package(name:)` string must be a
///    kebab-case slug — `[a-z0-9]+(-[a-z0-9]+)*` (e.g.
///    `swift-institute-linter-rules`, `institute-application`, and the
///    nested test manifest's `testing`).
/// 2. **Product/target names**: the `name:` string of every product
///    factory (`.library`, `.executable`, `.plugin`) and target factory
///    (`.target`, `.testTarget`, `.executableTarget`, `.macro`,
///    `.plugin`, and — per the C-shim naming ruling, #65 principal
///    ruling 2026-08-10 — `.systemLibrary`) declared by THIS package
///    must be a spaced Nest.Name
///    form: space-separated words, none of which is a concatenated
///    compound by the shared compound-word predicate
///    (`namingWordIsCompound`, the [API-NAME-001] owner — brand tokens
///    such as `GitHub` and spec forms are exempt there). Concatenated
///    forms (`InstituteArchitectureCLI`) are violations; the spaced
///    form (`Institute Architecture CLI`) and legitimately single-word
///    names (the executable `institute`) are not.
/// 3. **Declared-path correspondence** (the manifest half of the
///    Nest.Name directory ruling of 2026-08-06): when a target factory
///    carries an explicit `path:` string literal, and that path's last
///    segment differs from the declared target name ONLY by spacing
///    (segment == name with its spaces removed, or vice versa), the
///    concatenated side is a violation — a concatenated directory under
///    a spaced target, or a spaced directory under a concatenated
///    target. A path whose last segment differs in substance (the
///    settled `Tests/Support` convention for test-support targets) is
///    out of this predicate's reach and deliberately silent — recorded
///    residue, not compliance.
///
/// NOT policed (by predicate, not exemption): dependency references —
/// `.product(name:package:)` names third-party products and
/// `.package(url:)` names third-party packages; their spellings are the
/// upstream owner's. Only names this manifest declares are in scope.
///
/// Citation: `swift-institute-linter-rules#65`; Goal #94.
extension Lint.Rule {
    public static let `manifest naming grammar` = Lint.Rule(
        id: "manifest naming grammar",
        default: .warning,
        controls: [
            .init(
                id: "manifest naming grammar concatenated target",
                source: "let package = Package(name: \"swift-example\", "
                    + "targets: [.executableTarget(name: \"InstituteArchitectureCLI\")] )",
                path: "Package.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "manifest naming grammar spaced target",
                source: "let package = Package(name: \"swift-example\", "
                    + "targets: [.executableTarget(name: \"Institute Architecture CLI\")] )",
                path: "Package.swift",
                expectation: .clean
            ),
            .init(
                id: "manifest naming grammar upstream product",
                source: "let package = Package(name: \"swift-example\", "
                    + "targets: [.target(name: \"Consumer\", dependencies: "
                    + "[.product(name: \"OrderedCollections\", package: \"swift-collections\")])])",
                path: "Package.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            guard namingIsPackageManifest(source.file.filePath) else { return [] }
            let visitor = NamingManifestGrammarVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

/// Returns true when `name` is a kebab-case package slug:
/// `[a-z0-9]+(-[a-z0-9]+)*`.
internal func namingManifestIsKebabSlug(_ name: Swift.String) -> Swift.Bool {
    guard !name.isEmpty else { return false }
    var previousWasHyphen = true  // leading hyphen is invalid
    for character in name {
        if character == "-" {
            if previousWasHyphen { return false }
            previousWasHyphen = true
            continue
        }
        guard character.isLowercase || character.isNumber else { return false }
        guard character.isASCII else { return false }
        previousWasHyphen = false
    }
    return !previousWasHyphen  // trailing hyphen is invalid
}

/// Returns the space-separated words of `name` that are concatenated
/// compounds by the shared predicate. Empty when `name` is a
/// well-formed spaced Nest.Name form (or a single non-compound word).
internal func namingManifestCompoundWords(in name: Swift.String) -> [Swift.String] {
    name.split(separator: " ").map(Swift.String.init).filter(namingWordIsCompound)
}

@usableFromInline
internal func namingManifestGrammarSlugMessage(_ name: Swift.String) -> Swift.String {
    "[manifest naming grammar]: package name '\(name)' is not a kebab-case "
        + "slug — the package name must match `[a-z0-9]+(-[a-z0-9]+)*` "
        + "(e.g. `institute-application`)"
}

@usableFromInline
internal func namingManifestGrammarNameMessage(
    _ name: Swift.String,
    words: [Swift.String]
) -> Swift.String {
    "[manifest naming grammar]: declared name '\(name)' contains "
        + "concatenated word\(words.count == 1 ? "" : "s") "
        + words.map { "'\($0)'" }.joined(separator: ", ")
        + " — product and target names use the spaced Nest.Name form "
        + "(e.g. `Institute Architecture CLI`, not `InstituteArchitectureCLI`)"
}

@usableFromInline
internal func namingManifestGrammarPathMessage(
    name: Swift.String,
    segment: Swift.String
) -> Swift.String {
    "[manifest naming grammar]: target '\(name)' declares path segment "
        + "'\(segment)', which differs from the target name only by "
        + "spacing — the directory name must correspond exactly to the "
        + "declared spaced target name"
}

/// The product- and target-declaring manifest factory members whose
/// `name:` argument this rule inspects. `.product` is deliberately
/// absent: it references a dependency's product, which the upstream
/// owner names. `.systemLibrary` is present per the C-shim naming
/// ruling (#65, principal 2026-08-10): system-library targets take the
/// same spaced grammar as every other target; note that a single
/// lowercase word (`imagemagick`) is silent here by the grammar's own
/// single-word rule — the `* Shims` shape half of that ruling is the
/// validator family's predicate, not this rule's.
private let namingManifestDeclaringFactories: Swift.Set<Swift.String> = [
    "library", "executable", "target", "testTarget", "executableTarget", "macro", "plugin",
    "systemLibrary",
]

/// The subset of factories that declare targets (and may carry `path:`).
private let namingManifestTargetFactories: Swift.Set<Swift.String> = [
    "target", "testTarget", "executableTarget", "macro", "plugin", "systemLibrary",
]

internal final class NamingManifestGrammarVisitor: SyntaxVisitor {
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

    /// Resolves an argument expression to a single-segment string
    /// literal's text, or nil for anything computed.
    private func literalText(_ expression: ExprSyntax) -> (Swift.String, AbsolutePosition)? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            let segment = literal.segments.first?.as(StringSegmentSyntax.self)
        else { return nil }
        return (segment.content.text, literal.positionAfterSkippingLeadingTrivia)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Top-level `Package(name:)` — the kebab-slug predicate.
        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self),
            reference.baseName.text == "Package"
        {
            for argument in node.arguments where argument.label?.text == "name" {
                guard let (name, position) = literalText(argument.expression) else { continue }
                if !namingManifestIsKebabSlug(name) {
                    emit(at: position, message: namingManifestGrammarSlugMessage(name))
                }
            }
            return .visitChildren
        }
        // Product/target factories — the spaced-name and path predicates.
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            namingManifestDeclaringFactories.contains(member.declName.baseName.text)
        else { return .visitChildren }
        var declaredName: Swift.String?
        for argument in node.arguments where argument.label?.text == "name" {
            guard let (name, position) = literalText(argument.expression) else { continue }
            declaredName = name
            let compounds = namingManifestCompoundWords(in: name)
            if !compounds.isEmpty {
                emit(
                    at: position,
                    message: namingManifestGrammarNameMessage(name, words: compounds)
                )
            }
        }
        if namingManifestTargetFactories.contains(member.declName.baseName.text),
            let name = declaredName
        {
            for argument in node.arguments where argument.label?.text == "path" {
                guard let (path, position) = literalText(argument.expression) else { continue }
                guard
                    let segment = path.split(separator: "/", omittingEmptySubsequences: true).last
                        .map(Swift.String.init)
                else { continue }
                let despacedSegment = Swift.String(segment.filter { $0 != " " })
                let despacedName = Swift.String(name.filter { $0 != " " })
                if segment != name, despacedSegment == despacedName {
                    emit(
                        at: position,
                        message: namingManifestGrammarPathMessage(name: name, segment: segment)
                    )
                }
            }
        }
        return .visitChildren
    }

    private func emit(at position: AbsolutePosition, message: Swift.String) {
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
                identifier: "manifest naming grammar",
                message: message
            )
        )
    }
}
