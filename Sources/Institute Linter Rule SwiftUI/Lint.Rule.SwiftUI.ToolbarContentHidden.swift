public import Lint
internal import SwiftSyntax

extension Lint.Rule {
    public static let `toolbar content hidden` = Lint.Rule(
        id: "toolbar content hidden",
        default: .warning,
        controls: [
            .init(
                id: "toolbar content hidden ToolbarItem modifier",
                source: "ToolbarItem { Text(\"Select\") }.hidden(isSelecting)",
                path: "Sources/App/Toolbar.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "toolbar content hidden ordinary view",
                source: "Text(\"Details\").hidden(isCollapsed)",
                path: "Sources/App/Details.swift",
                expectation: .clean
            ),
            .init(
                id: "toolbar content hidden false inside toolbar closure",
                source: "ContentView().toolbar { Text(\"Selection\").hidden(false) }",
                path: "Sources/App/Toolbar.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = SwiftUIToolbarContentHiddenVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

@usableFromInline
internal let swiftUIToolbarContentHiddenMessage: Swift::String =
    "[toolbar content hidden] [SWIFTUI-TOOLBAR-CONTENT-HIDDEN]: `.hidden(...)` is attached "
    + "to a `ToolbarItem`, `ToolbarItemGroup`, `ToolbarSpacer`, or `DefaultToolbarItem`, "
    + "or occurs inside a `.toolbar { ... }` closure. Express the mode as which items exist "
    + "(`if` in the `ToolbarContentBuilder`) so the system morphs the bar."

internal final class SwiftUIToolbarContentHiddenVisitor: SyntaxVisitor {
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

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "hidden"
        else { return .visitChildren }
        guard Self.isToolbarContent(member.base) || Self.isInsideToolbarClosure(node) else {
            return .visitChildren
        }

        let location = converter.location(for: member.declName.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "toolbar content hidden",
                message: swiftUIToolbarContentHiddenMessage
            )
        )
        return .visitChildren
    }

    private static let toolbarContentNames: Swift::Set<Swift::String> = [
        "DefaultToolbarItem",
        "ToolbarItem",
        "ToolbarItemGroup",
        "ToolbarSpacer",
    ]

    private static func calleeName(_ expression: ExprSyntax) -> Swift::String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return calleeName(specialization.expression)
        }
        return nil
    }

    private static func isToolbarContent(_ expression: ExprSyntax?) -> Swift::Bool {
        guard let expression, let call = expression.as(FunctionCallExprSyntax.self) else {
            return false
        }
        if let name = calleeName(call.calledExpression), toolbarContentNames.contains(name) {
            return true
        }
        guard let modifier = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return isToolbarContent(modifier.base)
    }

    private static func isInsideToolbarClosure(_ node: FunctionCallExprSyntax) -> Swift::Bool {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let closure = candidate.as(ClosureExprSyntax.self),
                let call = owningCall(of: closure),
                calleeName(call.calledExpression) == "toolbar"
            {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    private static func owningCall(of closure: ClosureExprSyntax) -> FunctionCallExprSyntax? {
        var current = closure.parent
        while let candidate = current {
            if let call = candidate.as(FunctionCallExprSyntax.self) {
                return call
            }
            if candidate.is(ClosureExprSyntax.self) {
                return nil
            }
            current = candidate.parent
        }
        return nil
    }
}
