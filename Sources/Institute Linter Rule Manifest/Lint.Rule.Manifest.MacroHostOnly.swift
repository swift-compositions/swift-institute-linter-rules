public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `macro host only` = Lint.Rule(
        id: "macro host only",
        default: .warning,
        controls: [
            .init(
                id: "macro host only shared dependency",
                source: "let package = Package(targets: ["
                    + ".target(name: \"Shared\"), "
                    + ".macro(name: \"Feature Macros\", dependencies: [.target(name: \"Shared\")]), "
                    + ".target(name: \"Feature\", dependencies: [.target(name: \"Shared\")])])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "macro host only isolated dependency",
                source: "let package = Package(targets: ["
                    + ".target(name: \"Macro Core\", dependencies: ["
                    + ".product(name: \"SwiftSyntax\", package: \"swift-syntax\")]), "
                    + ".macro(name: \"Feature Macros\", dependencies: ["
                    + ".target(name: \"Macro Core\"), "
                    + ".product(name: \"SwiftCompilerPlugin\", package: \"swift-syntax\")])])",
                path: "Package.swift",
                expectation: .clean
            ),
            .init(
                id: "macro host only near miss swift syntax fork",
                source: "let package = Package(targets: ["
                    + ".macro(name: \"Feature Macros\", dependencies: ["
                    + ".product(name: \"SwiftSyntax\", package: \"swift-syntax-fork\")])])",
                path: "Package.swift",
                expectation: .findings(1)
            ),
        ],
        observe: { source, severity in
            guard
                manifestIsPackageManifest(
                    source.file.filePath,
                    path: source.path.underlying,
                    text: source.tree.description
                )
            else {
                return Lint.Rule.Observation(
                    findings: [],
                    coverage: .measured,
                    applicability: .inapplicable
                )
            }
            if let shape = manifestUnmeasurableShape(source.tree) {
                return Lint.Rule.Observation(
                    findings: [],
                    coverage: .unmeasured(.unsupportedSourceShape(shape))
                )
            }
            let visitor = ManifestMacroHostOnlyVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.collectManifestAccessors(source.tree)
            visitor.walk(source.tree)
            let findings = visitor.resolvedMatches()
            let coverage: Lint.Rule.Coverage =
                visitor.unhandledSourceShape.map {
                    .unmeasured(.unsupportedSourceShape($0))
                } ?? .measured
            return Lint.Rule.Observation(findings: findings, coverage: coverage)
        }
    )
}

internal let manifestMacroHostOnlyMessage: Swift::String =
    "[macro host only]: in this Package.swift, a `.macro` target may depend only on "
    + "swift-syntax products and same-package targets used only by macros or their tests; "
    + "a test target that depends on a `.macro` target may not also depend on another "
    + "same-package library target; a macro-only support target may not also be used by "
    + "a non-macro target; and, as a per-manifest approximation, a non-test library "
    + "target may not depend on InlineSnapshotTesting, MacroTesting, or a swift-syntax "
    + "product unless only macros or their tests use it. Cross-package transitive reach "
    + "is not checked."

internal final class ManifestMacroHostOnlyVisitor: SyntaxVisitor {
    private enum Kind: Equatable {
        case macro
        case test
        case library
        case other
    }

    private struct Dependency {
        let localName: Swift::String?
        let productName: Swift::String?
        let packageName: Swift::String?
        let position: AbsolutePosition
    }

    private struct Target {
        let name: Swift::String
        let kind: Kind
        let dependencies: [Dependency]
    }

    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var unhandledSourceShape: Swift::String?

    private var targets: [Target] = []
    private var stringStaticAccessorBodies: [Swift::String: ExprSyntax] = [:]
    private var stringInstanceAccessorBodies: [Swift::String: ExprSyntax] = [:]
    private var dependencyAccessorBodies: [Swift::String: ExprSyntax] = [:]
    private var fileScopeBindings: [Swift::String: ExprSyntax] = [:]
    private var swiftSyntaxPackageNames: Swift::Set<Swift::String> = ["swift-syntax"]

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    internal func collectManifestAccessors(_ file: SourceFileSyntax) {
        stringStaticAccessorBodies = manifestAccessorBodies(
            in: file,
            extendedTypes: ["String", "Swift.String"],
            static: true
        )
        stringInstanceAccessorBodies = manifestAccessorBodies(
            in: file,
            extendedTypes: ["String", "Swift.String"],
            static: false
        )
        dependencyAccessorBodies = manifestAccessorBodies(
            in: file,
            extendedTypes: ["Target.Dependency", "PackageDescription.Target.Dependency"],
            static: true
        )
        for statement in Lint.Syntax.Conditional.statements(file.statements) {
            guard let variable = statement.item.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                    let initializer = binding.initializer?.value
                else { continue }
                fileScopeBindings[pattern.identifier.text] = initializer
            }
        }
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }
        if member.declName.baseName.text == "package" {
            recordPackage(node)
            return .visitChildren
        }
        guard
            !isNestedInsideDependenciesArgument(Syntax(node)),
            let kind = targetKind(member.declName.baseName.text)
        else { return .visitChildren }
        recordTarget(node, kind: kind)
        return .visitChildren
    }

    internal func resolvedMatches() -> [Diagnostic.Record] {
        let names = Swift::Set(targets.map(\.name))
        var matches: [Diagnostic.Record] = []

        for target in targets where target.kind == .macro {
            for dependency in target.dependencies {
                if let localName = dependency.localName, names.contains(localName) {
                    continue
                }
                guard !isSwiftSyntaxProduct(dependency) else { continue }
                matches.append(record(at: dependency.position))
            }
        }

        for target in targets where target.kind == .test {
            let localDependencies = target.dependencies.compactMap { dependency in
                dependency.localName.flatMap { name in
                    targets.first(where: { $0.name == name })
                }.map { (dependency, $0) }
            }
            guard localDependencies.contains(where: { $0.1.kind == .macro }) else { continue }
            for (dependency, dependedOn) in localDependencies where dependedOn.kind == .library {
                matches.append(record(at: dependency.position))
            }
        }

        let macroSupportNames = Swift::Set(
            targets.filter { $0.kind == .macro }.flatMap { target in
                target.dependencies.compactMap { dependency in
                    dependency.localName.map { names.contains($0) } == true
                        ? dependency.localName
                        : nil
                }
            }
        )
        for target in targets where target.kind != .macro && target.kind != .test {
            for dependency in target.dependencies {
                guard let localName = dependency.localName,
                    macroSupportNames.contains(localName)
                else { continue }
                matches.append(record(at: dependency.position))
            }
        }

        for target in targets where target.kind == .library {
            guard !isUsedOnlyByMacrosOrTests(target.name) else { continue }
            for dependency in target.dependencies where isSensitiveProduct(dependency) {
                matches.append(record(at: dependency.position))
            }
        }

        return matches
    }

    private func recordTarget(_ node: FunctionCallExprSyntax, kind: Kind) {
        guard let nameArgument = node.arguments.first(where: { $0.label?.text == "name" }),
            let name = resolvedString(nameArgument.expression)
        else {
            unhandledSourceShape = unhandledSourceShape ?? "computed target name"
            return
        }
        var dependencies: [Dependency] = []
        for argument in node.arguments where argument.label?.text == "dependencies" {
            for expression in resolvedElements(argument.expression) {
                if let dependency = resolvedDependency(expression) {
                    dependencies.append(dependency)
                }
            }
        }
        targets.append(Target(name: name, kind: kind, dependencies: dependencies))
    }

    private func recordPackage(_ node: FunctionCallExprSyntax) {
        guard let urlArgument = node.arguments.first(where: { $0.label?.text == "url" }),
            let url = resolvedString(urlArgument.expression),
            manifestGitHubRepository(url) == "swiftlang/swift-syntax"
        else { return }
        let name =
            node.arguments.first(where: { $0.label?.text == "name" })
            .flatMap { resolvedString($0.expression) }
            ?? "swift-syntax"
        swiftSyntaxPackageNames.insert(name)
    }

    private func targetKind(_ factory: Swift::String) -> Kind? {
        switch factory {
        case "macro": .macro
        case "testTarget": .test
        case "target": .library
        case "executableTarget", "plugin", "systemLibrary", "binaryTarget": .other
        default: nil
        }
    }

    private func resolvedElements(
        _ expression: ExprSyntax,
        visited: Swift::Set<Swift::String> = []
    ) -> [ExprSyntax] {
        if let array = expression.as(ArrayExprSyntax.self) {
            return array.elements.map(\.expression)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            guard !visited.contains(name), let body = fileScopeBindings[name] else {
                unhandledSourceShape =
                    unhandledSourceShape
                    ?? "unresolved dependency array reference '\(name)'"
                return []
            }
            return resolvedElements(body, visited: visited.union([name]))
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return sequence.elements
                .filter { $0.as(BinaryOperatorExprSyntax.self) == nil }
                .flatMap { resolvedElements($0, visited: visited) }
        }
        unhandledSourceShape =
            unhandledSourceShape
            ?? "computed dependency array '\(expression.trimmedDescription)'"
        return []
    }

    private func resolvedDependency(
        _ expression: ExprSyntax,
        visited: Swift::Set<Swift::String> = []
    ) -> Dependency? {
        if let literal = expression.as(StringLiteralExprSyntax.self),
            let name = manifestStringLiteralText(literal)
        {
            return Dependency(
                localName: name,
                productName: nil,
                packageName: nil,
                position: expression.positionAfterSkippingLeadingTrivia
            )
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self)
        {
            let factory = member.declName.baseName.text
            if factory == "target" || factory == "byName" {
                guard
                    let argument = call.arguments.first(where: {
                        $0.label?.text == "name" || $0.label == nil
                    }), let name = resolvedString(argument.expression)
                else {
                    unhandledSourceShape =
                        unhandledSourceShape
                        ?? "computed local target dependency '\(expression.trimmedDescription)'"
                    return nil
                }
                return Dependency(
                    localName: name,
                    productName: nil,
                    packageName: nil,
                    position: expression.positionAfterSkippingLeadingTrivia
                )
            }
            if factory == "product" || factory == "plugin" {
                guard let argument = call.arguments.first(where: { $0.label?.text == "name" }),
                    let name = resolvedString(argument.expression)
                else {
                    unhandledSourceShape =
                        unhandledSourceShape
                        ?? "computed product dependency '\(expression.trimmedDescription)'"
                    return nil
                }
                let package = call.arguments.first(where: { $0.label?.text == "package" })
                    .flatMap { resolvedString($0.expression) }
                return Dependency(
                    localName: nil,
                    productName: name,
                    packageName: package,
                    position: expression.positionAfterSkippingLeadingTrivia
                )
            }
        }
        if let member = expression.as(MemberAccessExprSyntax.self), member.base == nil {
            let name = member.declName.baseName.text
            guard !visited.contains(name), let body = dependencyAccessorBodies[name] else {
                unhandledSourceShape =
                    unhandledSourceShape
                    ?? "unresolved target dependency accessor '\(name)'"
                return nil
            }
            return resolvedDependency(body, visited: visited.union([name])).map {
                Dependency(
                    localName: $0.localName,
                    productName: $0.productName,
                    packageName: $0.packageName,
                    position: expression.positionAfterSkippingLeadingTrivia
                )
            }
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            guard !visited.contains(name), let body = fileScopeBindings[name] else {
                unhandledSourceShape =
                    unhandledSourceShape
                    ?? "unresolved target dependency reference '\(name)'"
                return nil
            }
            return resolvedDependency(body, visited: visited.union([name])).map {
                Dependency(
                    localName: $0.localName,
                    productName: $0.productName,
                    packageName: $0.packageName,
                    position: expression.positionAfterSkippingLeadingTrivia
                )
            }
        }
        unhandledSourceShape =
            unhandledSourceShape
            ?? "unhandled target dependency '\(expression.trimmedDescription)'"
        return nil
    }

    private func resolvedString(_ expression: ExprSyntax) -> Swift::String? {
        manifestResolvedString(
            expression,
            staticAccessors: stringStaticAccessorBodies,
            instanceAccessors: stringInstanceAccessorBodies,
            unhandledSourceShape: &unhandledSourceShape
        )
    }

    private func isUsedOnlyByMacrosOrTests(_ name: Swift::String) -> Swift::Bool {
        var usedByMacro = false
        for target in targets {
            guard target.dependencies.contains(where: { $0.localName == name }) else { continue }
            switch target.kind {
            case .macro: usedByMacro = true
            case .test: continue
            case .library, .other: return false
            }
        }
        return usedByMacro
    }

    private func isSwiftSyntaxProduct(_ dependency: Dependency) -> Swift::Bool {
        dependency.productName != nil
            && dependency.packageName.map { swiftSyntaxPackageNames.contains($0) } == true
    }

    private func isSensitiveProduct(_ dependency: Dependency) -> Swift::Bool {
        isSwiftSyntaxProduct(dependency)
            || dependency.productName == "InlineSnapshotTesting"
            || dependency.productName == "MacroTesting"
    }

    private func isNestedInsideDependenciesArgument(_ node: Syntax) -> Swift::Bool {
        var current = node.parent
        while let candidate = current {
            if let labeled = candidate.as(LabeledExprSyntax.self),
                labeled.label?.text == "dependencies"
            {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    private func record(at position: AbsolutePosition) -> Diagnostic.Record {
        let location = converter.location(for: position)
        return Diagnostic.Record(
            location: Source.Location(
                fileID: source.fileID,
                filePath: source.filePath,
                line: location.line,
                column: location.column
            ),
            severity: severity,
            identifier: "macro host only",
            message: manifestMacroHostOnlyMessage
        )
    }
}
