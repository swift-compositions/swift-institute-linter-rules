internal import SwiftSyntax

extension SQL.Graph {
    internal final class Visitor: SyntaxVisitor {
        private var accessors: [Swift::String: ExprSyntax] = [:]
        internal var executableProductTargets: Swift::Set<Swift::String> = []
        internal var executableTargets: Swift::Set<Swift::String> = []
        internal var sourceRoots: [Swift::String: Swift::String] = [:]
        internal var targets: Swift::Set<Swift::String> = []

        internal init(_ tree: SourceFileSyntax) {
            super.init(viewMode: .sourceAccurate)
            collectAccessors(tree)
            walk(tree)
        }

        override func visit(
            _ node: FunctionCallExprSyntax
        ) -> SyntaxVisitorContinueKind {
            guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
                return .visitChildren
            }
            switch member.declName.baseName.text {
            case "executable":
                guard isInside("products", node) else { return .visitChildren }
                executableProductTargets.formUnion(targetList(node))
            case "executableTarget":
                guard isInside("targets", node) else { return .visitChildren }
                recordTarget(node, executable: true)
            case "target":
                guard isInside("targets", node) else { return .visitChildren }
                recordTarget(node, executable: false)
            default:
                break
            }
            return .visitChildren
        }

        private func collectAccessors(_ tree: SourceFileSyntax) {
            for statement in tree.statements {
                guard let declaration = statement.item.as(ExtensionDeclSyntax.self),
                    ["String", "Swift.String"].contains(declaration.extendedType.trimmedDescription)
                else { continue }
                for member in declaration.memberBlock.members {
                    guard let variable = member.decl.as(VariableDeclSyntax.self),
                        variable.modifiers.contains(where: {
                            $0.name.tokenKind == .keyword(.static)
                        })
                    else { continue }
                    for binding in variable.bindings {
                        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                            let value = binding.initializer?.value
                        else { continue }
                        accessors[name] = value
                    }
                }
            }
        }

        private func recordTarget(_ node: FunctionCallExprSyntax, executable: Swift::Bool) {
            guard let name = argument("name", in: node).flatMap(resolve) else { return }
            targets.insert(name)
            if executable { executableTargets.insert(name) }
            if let path = argument("path", in: node).flatMap(resolve) {
                sourceRoots[name] = path.trimmingPrefix("./").trimmingSuffix("/")
            }
        }

        private func targetList(_ node: FunctionCallExprSyntax) -> [Swift::String] {
            guard let expression = argument("targets", in: node),
                let array = expression.as(ArrayExprSyntax.self)
            else { return [] }
            return array.elements.compactMap { resolve($0.expression) }
        }

        private func argument(
            _ label: Swift::String,
            in node: FunctionCallExprSyntax
        ) -> ExprSyntax? {
            node.arguments.first(where: { $0.label?.text == label })?.expression
        }

        private func resolve(_ expression: ExprSyntax) -> Swift::String? {
            if let literal = expression.as(StringLiteralExprSyntax.self),
                literal.segments.count == 1,
                let segment = literal.segments.first?.as(StringSegmentSyntax.self)
            {
                return segment.content.text
            }
            if let member = expression.as(MemberAccessExprSyntax.self), member.base == nil,
                let value = accessors[member.declName.baseName.text]
            {
                return resolve(value)
            }
            return nil
        }

        private func isInside(
            _ label: Swift::String,
            _ node: FunctionCallExprSyntax
        ) -> Swift::Bool {
            var current = Syntax(node).parent
            while let candidate = current {
                if let argument = candidate.as(LabeledExprSyntax.self) {
                    return argument.label?.text == label
                }
                current = candidate.parent
            }
            return false
        }
    }
}

extension Swift::String {
    fileprivate func trimmingPrefix(_ prefix: Swift::String) -> Swift::String {
        hasPrefix(prefix) ? Swift::String(dropFirst(prefix.count)) : self
    }

    fileprivate func trimmingSuffix(_ suffix: Swift::String) -> Swift::String {
        hasSuffix(suffix) ? Swift::String(dropLast(suffix.count)) : self
    }
}
