public import Lint

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
        observe: { _, _ in
            Lint.Rule.Observation(findings: [], coverage: .measured)
        }
    )
}
