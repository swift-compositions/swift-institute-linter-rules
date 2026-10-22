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

public import Lint

extension Lint.Rule {
    public static let `binding get set` = Lint.Rule(
        id: "binding get set",
        default: .warning,
        controls: [
            .init(
                id: "binding get set custom construction",
                source: "let value = Binding(get: { model.value }, set: { model.value = $0 })",
                path: "Sources/Feature/CustomBinding.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "binding get set projection",
                source: "View(value: $model.value)",
                path: "Sources/Feature/ProjectedBinding.swift",
                expectation: .clean
            ),
            .init(
                id: "binding get set qualified near miss",
                source: "let value = SwiftUI.Binding<Bool>(get: { model.value }, set: { model.value = $0 })",
                path: "Sources/Feature/QualifiedCustomBinding.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { _, _ in [] }
    )
}
