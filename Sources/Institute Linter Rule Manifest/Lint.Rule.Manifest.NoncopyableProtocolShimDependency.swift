public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `noncopyable protocol shim dependency` = Lint.Rule(
        id: "noncopyable protocol shim dependency",
        default: .warning,
        controls: [
            .init(
                id: "noncopyable protocol shim dependency prohibited identities",
                source: "let package = Package(name: \"Fixture\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-molecules/swift-equation.git\", branch: \"main\"), "
                    + ".package(url: \"https://github.com/swift-molecules/swift-comparison.git\", branch: \"main\"), "
                    + ".package(url: \"https://github.com/swift-molecules/swift-hash.git\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .findings(3)
            ),
            .init(
                id: "noncopyable protocol shim dependency unrelated identity",
                source: "let package = Package(name: \"Fixture\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-atoms/swift-order.git\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .clean
            ),
            .init(
                id: "noncopyable protocol shim dependency noncanonical url",
                source: "let package = Package(name: \"Fixture\", dependencies: ["
                    + ".package(name: \"Comparison\", "
                    + "url: \"https://github.com/Swift-Molecules/Swift-Comparison.git/\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
        ],
        observe: { source, severity in
            guard manifestIsPackageManifest(
                source.file.filePath,
                path: source.path.underlying,
                text: source.tree.description
            ) else {
                return Lint.Rule.Observation(
                    findings: [],
                    coverage: .measured,
                    applicability: .inapplicable
                )
            }
            let visitor = ManifestNoncopyableProtocolShimDependencyVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            let coverage: Lint.Rule.Coverage =
                visitor.unhandledSourceShape.map {
                    .unmeasured(.unsupportedSourceShape($0))
                } ?? .measured
            return Lint.Rule.Observation(findings: visitor.matches, coverage: coverage)
        }
    )
}

private let manifestNoncopyableProtocolShimIdentities: Swift::Set<Swift::String> = [
    "swift-comparison",
    "swift-equation",
    "swift-hash",
]

private func manifestNoncopyableProtocolShimDependencyMessage(
    _ identity: Swift::String
) -> Swift::String {
    "[noncopyable protocol shim dependency]: package dependency identity "
        + "`\(identity)` is one of `swift-equation`, `swift-comparison`, or `swift-hash`; "
        + "use the corresponding Swift standard-library protocol when only noncopyable "
        + "protocol support is needed."
}

private final class ManifestNoncopyableProtocolShimDependencyVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    var unhandledSourceShape: Swift::String?

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "package",
            let argument = node.arguments.first(where: { $0.label?.text == "url" })
        else { return .visitChildren }
        guard let literal = argument.expression.as(StringLiteralExprSyntax.self),
            let url = manifestStringLiteralText(literal)
        else {
            unhandledSourceShape =
                unhandledSourceShape
                ?? "nonliteral package dependency url '\(argument.expression.trimmedDescription)'"
            return .visitChildren
        }
        guard let repository = manifestGitHubRepository(url),
            let identity = repository.split(separator: "/").last.map(Swift::String.init),
            manifestNoncopyableProtocolShimIdentities.contains(identity)
        else {
            return .visitChildren
        }
        let location = converter.location(for: argument.expression.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "noncopyable protocol shim dependency",
                message: manifestNoncopyableProtocolShimDependencyMessage(identity)
            )
        )
        return .visitChildren
    }
}
