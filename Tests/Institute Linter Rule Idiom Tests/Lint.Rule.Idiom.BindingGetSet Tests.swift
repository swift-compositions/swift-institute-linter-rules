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

@testable import Institute_Linter_Rule_Idiom

extension Lint.Rule {
    @Suite
    struct `binding get set Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`binding get set Tests` {
    static func findings(in source: Swift::String) -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source)
        return Lint.Rule.`binding get set`.observe(parsed, .warning).findings
    }
}

extension Lint.Rule.`binding get set Tests`.Unit {
    @Test
    func `custom Binding get set construction is flagged`() {
        let findings = Lint.Rule.`binding get set Tests`.findings(
            in: "let value = Binding(get: { model.value }, set: { model.value = $0 })"
        )
        #expect(findings.count == 1)
        #expect(findings.first?.identifier == "binding get set")
        #expect(findings.first?.severity == .warning)
        #expect(findings.first?.message == idiomBindingGetSetMessage)
    }

    @Test
    func `Binding wrapping an optional projection is flagged`() {
        let findings = Lint.Rule.`binding get set Tests`.findings(
            in: "if let value = Binding($model.optional) { use(value) }"
        )
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.`binding get set Tests`.`Edge Case` {
    @Test
    func `lawful derived bindings are silent`() {
        let source = """
            @Bindable var model = model
            View(value: $state, property: $model.property)
            let projected = $model[dynamicMember: \\.property]
            """
        let findings = Lint.Rule.`binding get set Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `qualified specialized custom Binding still fires`() {
        let findings = Lint.Rule.`binding get set Tests`.findings(
            in: "let value = SwiftUI.Binding<Bool>(get: { model.value }, set: { model.value = $0 })"
        )
        #expect(findings.count == 1)
    }

    @Test
    func `optional Binding held in a local still fires`() {
        let findings = Lint.Rule.`binding get set Tests`.findings(
            in: "if let value = Binding(optionalBinding) { use(value) }"
        )
        #expect(findings.count == 1)
    }
}
