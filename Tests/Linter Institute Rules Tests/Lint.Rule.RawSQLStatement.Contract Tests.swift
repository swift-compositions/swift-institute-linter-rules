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

import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Linter_Institute_Rules

@Suite
struct `Raw SQL statement Contract Tests` {
    private var rule: Lint.Rule? {
        Lint.Rule.Bundle.institute
            .map(\.rule)
            .first { $0.id.underlying == "raw sql statement" }
    }

    private func findings(
        _ source: Swift::String,
        file: Swift::String = "Sources/Database/Query.swift"
    ) -> [Diagnostic.Record] {
        guard let rule else { return [] }
        return rule.observe(Lint.Source.parsed(from: source, file: file), .warning).findings
    }

    @Test
    func `whole statement literal is a violation`() {
        #expect(rule.map { _ in true } == true)
        #expect(findings("let query = #sql(\"SELECT * FROM records\")").count == 1)
    }

    @Test
    func `frozen migration history and typed query are lawful`() {
        #expect(
            findings(
                "try database.execute(sql: \"CREATE TABLE records (id INTEGER)\")",
                file: "Sources/Database/Migrations/001_CreateRecords.swift"
            ).isEmpty
        )
        #expect(findings("let query = Record.select(Record.Columns.id)").isEmpty)
    }

    @Test
    func `qualified GRDB request near miss still fires`() {
        #expect(
            findings(
                "let request = GRDB.SQLRequest<Row>(sql: \"  select * FROM records\")"
            ).count == 1
        )
    }
}
