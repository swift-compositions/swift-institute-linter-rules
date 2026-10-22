public import Lint

extension Lint.Rule {
    public static let `macro expansion short name` = Lint.Rule(
        id: "macro expansion short name",
        default: .warning,
        controls: [
            .init(
                id: "macro expansion short name unqualified extension target",
                source: """
                    struct ValueMacro: ExtensionMacro {
                        static func expansion() -> [ExtensionDeclSyntax] {
                            ["extension Value: Swift.Sendable {}"]
                        }
                    }
                    """,
                path: "Sources/Value Macros/ValueMacro.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "macro expansion short name fully qualified types",
                source: """
                    struct ValueMacro: ExtensionMacro {
                        static func expansion() -> [ExtensionDeclSyntax] {
                            ["extension Domain.Value: Swift.Sendable {}"]
                        }
                    }
                    """,
                path: "Sources/Value Macros/ValueMacro.swift",
                expectation: .clean
            ),
            .init(
                id: "macro expansion short name unqualified inherited type",
                source: """
                    struct ValueMacro: ExtensionMacro {
                        static func expansion() -> [ExtensionDeclSyntax] {
                            ["extension Domain.Value: Sendable {}"]
                        }
                    }
                    """,
                path: "Sources/Value Macros/ValueMacro.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "macro expansion short name non macro code",
                source: """
                    struct Builder {
                        static func expansion() -> Swift.String {
                            "extension Value: Swift.Sendable {}"
                        }
                    }
                    """,
                path: "Sources/Builder/Builder.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { _, _ in [] }
    )
}

internal func namingMacroExpansionShortNameMessage(_ name: Swift::String) -> Swift::String {
    "[macro expansion short name]: macro-generated source refers to the type `\(name)` by a "
        + "short or unqualified name; spell the full type name."
}
