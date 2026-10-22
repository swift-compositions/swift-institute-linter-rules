import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_SQL

extension Lint.Rule {
    @Suite
    struct `sql execution in library target Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`sql execution in library target Tests` {
    static func findings(
        _ source: Swift::String,
        fixture: Swift::String,
        path: Swift::String = "Sources/Records/Records.swift"
    ) -> [Diagnostic.Record] {
        let testFile = Swift::String(#filePath)
        let directory = Swift::String(
            testFile.dropLast("Lint.Rule.SQL.Execution Tests.swift".count)
        )
        let file = directory + "Fixtures/" + fixture + "/" + path
        let parsed = Lint.Source.parsed(from: source, file: file, path: .init(path))
        return Lint.Rule.`sql execution in library target`
            .observe(parsed, .warning).findings
    }
}

extension Lint.Rule.`sql execution in library target Tests`.Unit {
    @Test
    func `violation fixture fires for every closed set member`() {
        let source = """
            func run() throws {
                try database.fetchAll(all)
                try database.fetchOne(one)
                try database.fetchCount(count)
                try database.fetchSet(set)
                try database.execute(statement)
            }
            """
        let findings = Lint.Rule.`sql execution in library target Tests`.findings(
            source,
            fixture: "Library"
        )
        #expect(findings.count == 5)
        #expect(findings.allSatisfy { $0.severity == .warning })
        #expect(
            findings.allSatisfy {
                $0.message
                    == "[sql execution in library target]: `fetchAll`, `fetchOne`, "
                    + "`fetchCount`, `fetchSet`, and `execute` calls are permitted only "
                    + "in executable and app targets; return a SQL statement or query "
                    + "value from library targets and execute it at the edge."
            }
        )
    }

    @Test
    func `lawful executable fixture is exempt`() {
        let findings = Lint.Rule.`sql execution in library target Tests`.findings(
            "func run() throws { try database.fetchAll(query) }",
            fixture: "Executable"
        )
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`sql execution in library target Tests`.`Edge Case` {
    @Test
    func `near miss library named app still fires`() {
        let findings = Lint.Rule.`sql execution in library target Tests`.findings(
            "func run() throws { try database.execute(statement) }",
            fixture: "App Named Library",
            path: "Sources/Laurie App/Save.swift"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `similar method names remain outside the closed set`() {
        let findings = Lint.Rule.`sql execution in library target Tests`.findings(
            "func run() { database.fetch(); database.fetchMany(); database.executeAll() }",
            fixture: "Library"
        )
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`sql execution in library target Tests`.Integration {
    @Test
    func `lawful app fixture outside package targets is exempt`() {
        let findings = Lint.Rule.`sql execution in library target Tests`.findings(
            "func run() throws { try database.fetchOne(query) }",
            fixture: "App",
            path: "Laurie/Records.swift"
        )
        #expect(findings.isEmpty)
    }
}
