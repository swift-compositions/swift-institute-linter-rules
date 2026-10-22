public import Lint
internal import SwiftSyntax

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
                id: "binding get set optional wrapping",
                source: "if let value = Binding($model.optional) { use(value) }",
                path: "Sources/Feature/OptionalBinding.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "binding get set qualified near miss",
                source: "let value = SwiftUI.Binding<Bool>(get: { model.value }, set: { model.value = $0 })",
                path: "Sources/Feature/QualifiedCustomBinding.swift",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = IdiomBindingGetSetVisitor(
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
internal let idiomBindingGetSetMessage: Swift::String =
    "[binding get set]: `Binding` is constructed with `get:set:` or with one "
    + "unlabeled argument (the optional-binding wrapper). Use `$state`, "
    + "`$model.property`, `@Bindable`, or key-path projection directly."

internal func idiomBindingCalleeName(_ expression: ExprSyntax) -> Swift::String? {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
        return member.declName.baseName.text
    }
    if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
        return idiomBindingCalleeName(specialization.expression)
    }
    return nil
}

internal final class IdiomBindingGetSetVisitor: SyntaxVisitor {
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
        guard idiomBindingCalleeName(node.calledExpression) == "Binding" else {
            return .visitChildren
        }
        let labels = node.arguments.map { $0.label?.text }
        let isCustomConstruction = labels == ["get", "set"]
        let isOptionalWrapping =
            node.arguments.count == 1
            && node.arguments.first?.label == nil
        guard isCustomConstruction || isOptionalWrapping else { return .visitChildren }

        let location = converter.location(
            for: node.calledExpression.positionAfterSkippingLeadingTrivia
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
                identifier: "binding get set",
                message: idiomBindingGetSetMessage
            )
        )
        return .visitChildren
    }
}
