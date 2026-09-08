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
internal import SwiftSyntax

/// A caseless `enum` is the institute's namespace shape: it is uninhabited,
/// so it can never have an instance. An *instance* member declared directly
/// inside one — an instance method, computed property, subscript, or an
/// initializer — is unreachable API surface: no call site can ever exist.
/// Citation: `[ARCH-FOUND-001]` (TX-A2, swift-compositions/swift-linter#44).
///
/// The shape violation is always one of two intents gone wrong:
///
/// - the author meant a namespace, and the member should be `static`;
/// - the author meant an inhabited type, and the declaration should be a
///   `struct` (or the enum should have cases).
///
/// Either way the declaration's shape contradicts its role, and the derived
/// architecture model (TX-A1) classifies the type by that role — a
/// "namespace" carrying phantom instance surface distorts the model's
/// public-API population (the record's zero-public-API classification edge
/// case is exactly this boundary).
///
/// AST-local and fully structural: casedness and member-level modifiers are
/// syntax. Enums WITH cases are never flagged (their instance members are
/// legitimate), and `static` members, nested types, typealiases and
/// deinitializers (which cannot occur here anyway) are not instance surface.
extension Lint.Rule {
    public static let `architecture namespace shape` = Lint.Rule(
        id: "architecture namespace shape",
        default: .warning,
        controls: [
            .init(
                id: "architecture namespace shape instance member",
                source: "public enum Render { public func run() {} }",
                path: "Sources/Architecture Core/InstanceMember.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "architecture namespace shape static member",
                source: "public enum Render { public static func run() {} }",
                path: "Sources/Architecture Core/StaticMember.swift",
                expectation: .clean
            ),
            .init(
                id: "architecture namespace shape inhabited enum",
                source: "public enum Render { case ready; public func run() {} }",
                path: "Sources/Architecture Core/InhabitedEnum.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = ArchitectureNamespaceShapeVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let architectureNamespaceShapeMessage: Swift.String =
    "[architecture namespace shape] [ARCH-FOUND-001]: a caseless enum is a "
    + "namespace — it is uninhabited, so this instance member can never be "
    + "called. Either mark the member `static` (namespace intent) or make the "
    + "type inhabited: add cases, or declare a `struct` (value intent)."

internal final class ArchitectureNamespaceShapeVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let members = node.memberBlock.members
        let hasCases = members.contains { member in
            member.decl.is(EnumCaseDeclSyntax.self)
        }
        // Inhabited enum: instance members are legitimate. Children are still
        // visited — a caseless enum nested inside a cased one is judged on its
        // own casedness.
        guard !hasCases else { return .visitChildren }
        // Exempt: a caseless enum WITH an inheritance clause may be a
        // Never-style uninhabited witness type — a protocol with instance
        // requirements forces uncallable instance witnesses to be DECLARED for
        // the conformance to compile. Those members are compiler-obligated, not
        // shape drift, and AST-locally the two are indistinguishable. Pure
        // namespaces carry no inheritance clause, so the rule's population is
        // exactly the namespace shape.
        guard node.inheritanceClause == nil else { return .visitChildren }
        for member in members {
            guard let offender = architectureNamespaceShapeInstanceMember(member.decl) else {
                continue
            }
            let location = converter.location(
                for: offender.positionAfterSkippingLeadingTrivia
            )
            matches.append(
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "architecture namespace shape",
                    message: architectureNamespaceShapeMessage
                )
            )
        }
        return .visitChildren
    }
}

/// Returns the declaration when it is *instance* surface — a non-`static`
/// function, variable, or subscript, or any initializer — and nil for
/// everything that is legitimate inside a namespace: `static` members,
/// nested types, typealiases, and macros.
private func architectureNamespaceShapeInstanceMember(
    _ declaration: DeclSyntax
) -> Syntax? {
    if let function = declaration.as(FunctionDeclSyntax.self) {
        return architectureNamespaceShapeIsTypeMember(function.modifiers)
            ? nil : Syntax(function)
    }
    if let variable = declaration.as(VariableDeclSyntax.self) {
        return architectureNamespaceShapeIsTypeMember(variable.modifiers)
            ? nil : Syntax(variable)
    }
    if let subscriptDeclaration = declaration.as(SubscriptDeclSyntax.self) {
        return architectureNamespaceShapeIsTypeMember(subscriptDeclaration.modifiers)
            ? nil : Syntax(subscriptDeclaration)
    }
    if let initializer = declaration.as(InitializerDeclSyntax.self) {
        // An initializer of an uninhabited type is uncallable regardless of
        // modifiers; `static` does not apply to `init`.
        return Syntax(initializer)
    }
    return nil
}

/// Returns true when the modifier list carries `static` (or `class`, its
/// reference-type spelling, which an enum cannot legally carry but which a
/// linter should not double-report on).
private func architectureNamespaceShapeIsTypeMember(
    _ modifiers: DeclModifierListSyntax
) -> Swift.Bool {
    modifiers.contains { modifier in
        modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
    }
}
