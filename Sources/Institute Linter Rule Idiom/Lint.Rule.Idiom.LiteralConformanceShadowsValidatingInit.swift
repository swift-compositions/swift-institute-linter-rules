public import Lint

extension Lint.Rule {
    public static let `literal conformance shadows validating init` = Lint.Rule(
        id: "literal conformance shadows validating init",
        default: .warning,
        controls: [
            .init(
                id: "literal conformance shadows validating init violation",
                source: "struct Value: ExpressibleByStringLiteral { init(_ value: some StringProtocol) throws {} }",
                path: "Sources/Idiom Core/Value.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "literal conformance shadows validating init lawful",
                source: "struct Value { init(_ value: some StringProtocol) throws {} }",
                path: "Sources/Idiom Core/Value.swift",
                expectation: .clean
            ),
            .init(
                id: "literal conformance shadows validating init near miss",
                source: "struct Value {}\nextension Value: Swift.ExpressibleByStringLiteral {}\nextension Value { init(_ value: some Swift.StringProtocol) throws(Value.Error) {} }",
                path: "Sources/Idiom Core/Value.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { _, _ in [] }
    )
}

@usableFromInline
internal let idiomLiteralConformanceShadowsValidatingInitMessage: Swift::String =
    "[literal conformance shadows validating init]: a type conforming to "
    + "`ExpressibleByStringLiteral` also declares a throwing "
    + "`init(_: some StringProtocol)`, so string-literal construction bypasses "
    + "that validating initializer. Remove the literal conformance."
