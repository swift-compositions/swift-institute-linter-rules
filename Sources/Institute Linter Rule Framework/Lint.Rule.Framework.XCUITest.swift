public import Lint

extension Lint.Rule {
    public static let `xcuitest reference` = Lint.Rule(
        id: "xcuitest reference",
        default: .warning,
        controls: [
            .init(
                id: "xcuitest reference application",
                source: "let application = XCUIApplication()",
                path: "Tests/Example UI Tests/Launch Tests.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "xcuitest reference lawful Swift Testing suite",
                source: "import Testing\n@Suite struct Launch { @Test func starts() {} }",
                path: "Tests/Example UI Tests/Launch Tests.swift",
                expectation: .clean
            ),
            .init(
                id: "xcuitest reference inside Swift Testing near miss",
                source: "import Testing\n@Test func starts() { _ = XCUIElement.self }",
                path: "Tests/Example UI Tests/Launch Tests.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "xcuitest reference element query",
                source: "let query: XCUIElementQuery",
                path: "Tests/Example UI Tests/Query Tests.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "xcuitest reference XCTest import",
                source: "import XCTest",
                path: "Tests/Example UI Tests/Launch Tests.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "xcuitest reference outside UI test target",
                source: "let application = XCUIApplication()",
                path: "Tests/Example Tests/Launch Tests.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { _, _ in [] }
    )
}
