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

@testable import Institute_Linter_Rule_SwiftUI

extension Lint.Rule {
    @Suite
    struct `toolbar content hidden Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`toolbar content hidden Tests` {
    static func findings(in source: String) -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source, file: "Sources/App/Toolbar.swift")
        return Lint.Rule.`toolbar content hidden`.observe(parsed, .warning).findings
    }
}

extension Lint.Rule.`toolbar content hidden Tests`.Unit {
    @Test
    func `hidden modifier on ToolbarItem is flagged`() {
        let source = """
            ToolbarItem(placement: .primaryAction) {
                Button("Select") {}
            }
            .hidden(isSelecting)
            """
        let findings = Lint.Rule.`toolbar content hidden Tests`.findings(in: source)
        #expect(findings.count == 1)
        #expect(findings.first?.severity == .warning)
    }

    @Test
    func `hidden modifier on an ordinary view outside toolbar content is permitted`() {
        let source = """
            Text("Details")
                .hidden(isCollapsed)
            """
        let findings = Lint.Rule.`toolbar content hidden Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `constant false hidden modifier inside toolbar closure still fires`() {
        let source = """
            ContentView()
                .toolbar {
                    Text("Selection")
                        .hidden(false)
                }
            """
        let findings = Lint.Rule.`toolbar content hidden Tests`.findings(in: source)
        #expect(findings.count == 1)
    }
}
