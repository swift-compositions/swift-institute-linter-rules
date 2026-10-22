public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `coder family layering` = Lint.Rule(
        id: "coder family layering",
        default: .warning,
        controls: [
            .init(
                id: "coder family layering violation",
                source: "let package = Package(name: \"swift-json-coder\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-atoms/swift-parser.git\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "coder family layering lawful dependency",
                source: "let package = Package(name: \"swift-json-coder\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-molecules/swift-json-parser.git\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .clean
            ),
            .init(
                id: "coder family layering near miss",
                source: "let package = Package(name: \"swift-json-coder\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-molecules/swift-json-parser-support.git\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "coder family layering parser product",
                source: "let package = Package(name: \"swift-json-parser\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-atoms/swift-coder.git\", branch: \"main\")], targets: ["
                    + ".target(name: \"JSON Parser\", dependencies: ["
                    + ".product(name: \"Serializer\", package: \"swift-coder\")])])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "coder family layering rfc domain",
                source: "let package = Package(name: \"swift-rfc-9112\", dependencies: ["
                    + ".package(url: \"https://github.com/swift-atoms/swift-parser.git\", branch: \"main\")])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "coder family layering rfc source declaration",
                source: "func parse(_ bytes: [UInt8]) {}",
                path: "/workspace/swift-ietf/swift-rfc-9112/Sources/RFC 9112/Parser.swift",
                expectation: .findings(1)
            ),
        ],
        observe: { source, severity in
            let isManifest = manifestIsPackageManifest(
                source.file.filePath,
                path: source.path.underlying,
                text: source.tree.description
            )
            let rfcDomain = manifestCoderFamilyRFCDomain(in: source.file.filePath)
            guard isManifest || rfcDomain != nil else {
                return Lint.Rule.Observation(
                    findings: [],
                    coverage: .measured,
                    applicability: .inapplicable
                )
            }
            let visitor = ManifestCoderFamilyLayeringVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter,
                packageName: rfcDomain,
                checksFunctions: !isManifest
            )
            visitor.walk(source.tree)
            return Lint.Rule.Observation(findings: visitor.matches, coverage: .measured)
        }
    )
}

private func manifestCoderFamilyRFCDomain(in path: Swift::String) -> Swift::String? {
    path.split(separator: "/")
        .map { $0.lowercased() }
        .first { $0.hasPrefix("swift-rfc-") && !$0.hasSuffix("-coder") }
}

internal final class ManifestCoderFamilyLayeringVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []
    private var packageName: Swift::String?
    private let checksFunctions: Swift::Bool

    init(
        source: Source.File,
        severity: Diagnostic.Severity,
        converter: SourceLocationConverter,
        packageName: Swift::String? = nil,
        checksFunctions: Swift::Bool = false
    ) {
        self.source = source
        self.severity = severity
        self.converter = converter
        self.packageName = packageName
        self.checksFunctions = checksFunctions
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard checksFunctions,
            let packageName,
            node.name.text == "parse" || node.name.text == "serialize"
        else { return .visitChildren }
        record(
            at: node.name.positionAfterSkippingLeadingTrivia,
            message: "[coder family layering]: `\(packageName)` must keep `parse` and `serialize` function declarations in its `\(packageName)-coder` sibling; found function `\(node.name.text)`."
        )
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Package" {
            packageName = node.arguments
                .first(where: { $0.label?.text == "name" })?
                .expression.as(StringLiteralExprSyntax.self)
                .flatMap { manifestStringLiteralText($0) }
                .map { $0.lowercased() }
            return .visitChildren
        }

        guard let packageName,
            let member = node.calledExpression.as(MemberAccessExprSyntax.self)
        else { return .visitChildren }

        switch member.declName.baseName.text {
        case "package": inspectDependency(node, owner: packageName)
        case "product": inspectProduct(node, owner: packageName)
        case "target", "executableTarget", "testTarget": inspectTarget(node, owner: packageName)
        default: break
        }
        return .visitChildren
    }

    private func inspectDependency(_ node: FunctionCallExprSyntax, owner: Swift::String) {
        guard let argument = node.arguments.first(where: { $0.label?.text == "url" }),
            let literal = argument.expression.as(StringLiteralExprSyntax.self),
            let url = manifestStringLiteralText(literal),
            let repository = manifestGitHubRepository(url),
            let dependency = repository.split(separator: "/").last.map(Swift::String.init)
        else { return }

        if owner.hasSuffix("-coder"), owner != "swift-coder" {
            let family = Swift::String(owner.dropLast("-coder".count))
            let allowed = Swift::Set([
                "swift-coder",
                family,
                family + "-parser",
                family + "-serializer",
            ])
            if !allowed.contains(dependency) {
                record(
                    at: literal.positionAfterSkippingLeadingTrivia,
                    message: "[coder family layering]: `\(owner)` may depend only on `swift-coder`, `\(family)`, `\(family)-parser`, and `\(family)-serializer`; found `\(dependency)`."
                )
            }
            return
        }

        if owner.hasSuffix("-parser"), dependency.hasSuffix("-serializer") {
            record(
                at: literal.positionAfterSkippingLeadingTrivia,
                message: "[coder family layering]: `\(owner)` must not depend on serializer packages or products; found dependency `\(dependency)`."
            )
            return
        }

        if isRFCDomain(owner), isWireCodingDependency(dependency) {
            record(
                at: literal.positionAfterSkippingLeadingTrivia,
                message: rfcMessage(owner: owner, finding: "dependency `\(dependency)`")
            )
        }
    }

    private func inspectProduct(_ node: FunctionCallExprSyntax, owner: Swift::String) {
        guard owner.hasSuffix("-parser"),
            let nameArgument = node.arguments.first(where: { $0.label?.text == "name" }),
            let nameLiteral = nameArgument.expression.as(StringLiteralExprSyntax.self),
            let name = manifestStringLiteralText(nameLiteral),
            name.lowercased().contains("serializer")
        else { return }
        let dependency = node.arguments
            .first(where: { $0.label?.text == "package" })?
            .expression.as(StringLiteralExprSyntax.self)
            .flatMap { manifestStringLiteralText($0) }
            ?? "unknown package"
        record(
            at: nameLiteral.positionAfterSkippingLeadingTrivia,
            message: "[coder family layering]: `\(owner)` must not depend on serializer packages or products; found product `\(name)` from `\(dependency)`."
        )
    }

    private func inspectTarget(_ node: FunctionCallExprSyntax, owner: Swift::String) {
        guard !isNestedInsideDependenciesArgument(Syntax(node)),
            isRFCDomain(owner),
            let argument = node.arguments.first(where: { $0.label?.text == "name" }),
            let literal = argument.expression.as(StringLiteralExprSyntax.self),
            let name = manifestStringLiteralText(literal),
            isWireCodingTarget(name)
        else { return }
        record(
            at: literal.positionAfterSkippingLeadingTrivia,
            message: rfcMessage(owner: owner, finding: "target `\(name)`")
        )
    }

    private func isNestedInsideDependenciesArgument(_ node: Syntax) -> Swift::Bool {
        var current = node.parent
        while let candidate = current {
            if let argument = candidate.as(LabeledExprSyntax.self),
                argument.label?.text == "dependencies"
            {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    private func record(at position: AbsolutePosition, message: Swift::String) {
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
                identifier: "coder family layering",
                message: message
            )
        )
    }

    private func isRFCDomain(_ name: Swift::String) -> Swift::Bool {
        name.hasPrefix("swift-rfc-") && !name.hasSuffix("-coder")
    }

    private func isWireCodingDependency(_ name: Swift::String) -> Swift::Bool {
        name == "swift-parser" || name == "swift-serializer" || name == "swift-coder"
            || name.hasSuffix("-parser") || name.hasSuffix("-serializer") || name.hasSuffix("-coder")
    }

    private func isWireCodingTarget(_ name: Swift::String) -> Swift::Bool {
        let words: Swift::Set<Swift::Substring> = Swift::Set(
            name.lowercased().split(whereSeparator: { !$0.isLetter })
        )
        return words.contains("parser") || words.contains("serializer") || words.contains("coder")
    }

    private func rfcMessage(owner: Swift::String, finding: Swift::String) -> Swift::String {
        "[coder family layering]: `\(owner)` must keep parsing and serializing dependencies and targets in its `\(owner)-coder` sibling; found \(finding)."
    }
}
