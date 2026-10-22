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
import SwiftParser
import SwiftSyntax
import Testing
import Text

@testable import Institute_Linter_Rule_Idiom

extension Lint.Rule {
    @Suite
    struct `leading dot builder statements Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`leading dot builder statements Tests` {
    static func findings(in source: String) -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source, file: "Route.swift")
        return Lint.Rule.`leading dot builder statements`.observe(parsed, .warning).findings
    }
}

extension Lint.Rule.`leading dot builder statements Tests`.Unit {
    @Test
    func `consecutive leading dot builder statements are flagged`() {
        let source = """
            route {
                .post
                .resource("greet")
            }
            """
        let findings = Lint.Rule.`leading dot builder statements Tests`.findings(in: source)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].identifier == "leading dot builder statements")
            #expect(findings[0].severity == .warning)
            #expect(findings[0].location.line == 3)
            #expect(findings[0].location.column == 5)
            #expect(
                findings[0].message
                    == "[leading dot builder statements]: a code-block expression starts with a "
                    + "leading-dot implicit member and continues on a later line with another "
                    + "dot-prefixed member, which Swift parses as one member chain; qualify the "
                    + "later member or insert an explicit expression boundary."
            )
        }
    }

    @Test
    func `type qualified builder statement is lawful`() {
        let source = """
            route {
                .post
                HTTP.Target.resource("greet")
            }
            """
        let findings = Lint.Rule.`leading dot builder statements Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `semicolon creates an explicit expression boundary`() {
        let source = """
            route {
                .post;
                .resource("greet")
            }
            """
        let findings = Lint.Rule.`leading dot builder statements Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`leading dot builder statements Tests`.`Edge Case` {
    @Test
    func `comment between leading dot lines does not create a boundary`() {
        let source = """
            route {
                .post
                // This comment does not end the expression.
                .resource("greet")
            }
            """
        let findings = Lint.Rule.`leading dot builder statements Tests`.findings(in: source)
        #expect(findings.count == 1)
    }
}
