import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Idiom

extension Lint.Rule {
    @Suite
    struct `raw sql statement Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`raw sql statement Tests` {
    static func findings(
        _ source: Swift::String,
        file: Swift::String = "Sources/Database/Query.swift"
    ) -> [Diagnostic.Record] {
        Lint.Rule.`raw sql statement`
            .observe(Lint.Source.parsed(from: source, file: file), .warning)
            .findings
    }
}

extension Lint.Rule.`raw sql statement Tests`.Unit {
    @Test
    func `full statement macro and GRDB forms are flagged`() {
        let source = """
            let select = #sql("SELECT * FROM records")
            try database.execute(sql: "INSERT INTO records VALUES (1)")
            let request = SQLRequest<Row>(sql: "UPDATE records SET id = 2")
            let rows = try Row.fetchAll(database, sql: "DELETE FROM records")
            """
        let findings = Lint.Rule.`raw sql statement Tests`.findings(source)
        #expect(findings.count == 4)
        #expect(findings.allSatisfy { $0.severity == .warning })
        #expect(findings.allSatisfy { $0.message == idiomRawSQLStatementMessage })
    }

    @Test
    func `all statement-leading keywords are flagged case insensitively`() {
        let source = """
            let select = #sql("select * FROM records")
            let insert = #sql("INSERT INTO records VALUES (1)")
            let update = #sql("UPDATE records SET id = 2")
            let delete = #sql("DELETE FROM records")
            let create = #sql("CREATE TABLE records (id INTEGER)")
            let pragma = #sql("PRAGMA foreign_keys = ON")
            """
        #expect(Lint.Rule.`raw sql statement Tests`.findings(source).count == 6)
    }
}

extension Lint.Rule.`raw sql statement Tests`.`Edge Case` {
    @Test
    func `leading whitespace qualified request still fires`() {
        let findings = Lint.Rule.`raw sql statement Tests`.findings(
            "let request = GRDB.SQLRequest<Row>(sql: \"  select * FROM records\")"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `interpolated statement still fires from its literal prefix`() {
        let findings = Lint.Rule.`raw sql statement Tests`.findings(
            "let query = #sql(\"SELECT * FROM \\(table)\")"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `SQL fragments and typed query construction are lawful`() {
        let source = """
            let column = #sql("created_at")
            let predicate = #sql("id = 1")
            let query = Record.select(Record.Columns.id)
            """
        #expect(Lint.Rule.`raw sql statement Tests`.findings(source).isEmpty)
    }

    @Test
    func `tests and frozen migration history are exempt`() {
        let statement = "try database.execute(sql: \"CREATE TABLE records (id INTEGER)\")"
        #expect(
            Lint.Rule.`raw sql statement Tests`.findings(
                statement,
                file: "Tests/Database Tests/Query Tests.swift"
            ).isEmpty
        )
        #expect(
            Lint.Rule.`raw sql statement Tests`.findings(
                statement,
                file: "Sources/Database/Migrations/001_CreateRecords.swift"
            ).isEmpty
        )
    }
}

extension Lint.Rule.`raw sql statement Tests`.Integration {
    @Test
    func `absolute application source path is checked`() {
        let findings = Lint.Rule.`raw sql statement Tests`.findings(
            "let rows = try GRDB.Row.fetchAll(database, sql: \"PRAGMA table_info(records)\")",
            file: "/workspace/database/Sources/Database/Query.swift"
        )
        #expect(findings.count == 1)
    }
}
