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

internal import Lint
internal import SwiftSyntax

/// Removes a duplicate display-name argument without changing the declaration
/// token that defines the test or suite's identity.
///
/// A differing display name is deliberately left alone. Replacing the
/// declaration token would rename the declaration and can affect references,
/// test filters, `#function`, and snapshot keys. The finding remains with its
/// rename-required disposition for reviewed or compiler-aware application.
internal func testingDisplayNameStringFixed(
    _ source: borrowing Lint.Source.Parsed
) -> Swift.String? {
    let rewriter = TestingDisplayNameStringRewriter()
    let rewritten = rewriter.visit(source.tree)
    guard rewriter.changed else { return nil }
    return rewritten.description
}

/// Rewrites only declaration-local duplicate-display shapes.
internal final class TestingDisplayNameStringRewriter: SyntaxRewriter {
    var changed: Swift.Bool = false

    /// Returns the declaration attributes with every binding-preserving display
    /// string removed, or the original list when no attribute is fixable.
    private func fixed(
        name: TokenSyntax,
        attributes: AttributeListSyntax
    ) -> AttributeListSyntax {
        var elements = Swift.Array(attributes)
        for index in elements.indices {
            guard case .attribute(let attribute) = elements[index] else { continue }
            guard let rewritten = fixed(name: name, attribute: attribute) else { continue }
            elements[index] = .attribute(rewritten)
            changed = true
        }
        return AttributeListSyntax(elements)
    }

    /// Removes the leading display argument when it duplicates `name` exactly.
    ///
    /// The leading-position guard mirrors the Testing macro contract. A later
    /// unlabelled string is not a display-name position the rewriter can prove,
    /// even if malformed source made the detector reach it.
    private func fixed(name: TokenSyntax, attribute: AttributeSyntax) -> AttributeSyntax? {
        let attributeName = attribute.attributeName.trimmedDescription
        guard
            ["Test", "Suite"].contains(where: {
                attributeName == $0 || attributeName.hasSuffix(".\($0)")
            })
        else { return nil }
        guard case .argumentList(let arguments) = attribute.arguments else { return nil }
        guard let argument = arguments.first, argument.label == nil else { return nil }
        guard let literal = argument.expression.as(StringLiteralExprSyntax.self) else { return nil }
        guard let content = testingDisplayNameContent(literal) else { return nil }
        guard displayNameCanBeRawIdentifier(content) else { return nil }
        guard testingDisplayNameDuplicatesDeclaration(name: name, content: content) else {
            return nil
        }

        let remaining = Swift.Array(arguments.dropFirst())
        if remaining.isEmpty {
            return removingOnlyArgument(argument, from: attribute)
        }
        return removingLeadingArgument(argument, remaining: remaining, from: attribute)
    }

    /// Drops an attribute's now-empty parentheses while carrying all authored
    /// trivia and the declaration-separating trivia onto the unchanged name.
    private func removingOnlyArgument(
        _ argument: LabeledExprSyntax,
        from attribute: AttributeSyntax
    ) -> AttributeSyntax? {
        guard let leftParen = attribute.leftParen, let rightParen = attribute.rightParen else {
            return nil
        }
        guard attribute.unexpectedBetweenAttributeNameAndLeftParen == nil,
            attribute.unexpectedBetweenLeftParenAndArguments == nil,
            attribute.unexpectedBetweenArgumentsAndRightParen == nil
        else { return nil }

        let carried =
            testingDisplayNameAuthoredTrivia(leftParen.leadingTrivia)
            + testingDisplayNameAuthoredTrivia(leftParen.trailingTrivia)
            + testingDisplayNameAuthoredTrivia(argument.leadingTrivia)
            + testingDisplayNameAuthoredTrivia(argument.trailingTrivia)
            + testingDisplayNameAuthoredTrivia(rightParen.leadingTrivia)
            + rightParen.trailingTrivia
        let name = attribute.attributeName.with(
            \.trailingTrivia,
            attribute.attributeName.trailingTrivia + carried
        )
        return
            attribute
            .with(\.attributeName, name)
            .with(\.leftParen, nil)
            .with(\.arguments, nil)
            .with(\.rightParen, nil)
    }

    /// Removes the display argument and its comma while keeping the layout and
    /// comments that lead into the first retained trait or `arguments:` value.
    private func removingLeadingArgument(
        _ argument: LabeledExprSyntax,
        remaining: [LabeledExprSyntax],
        from attribute: AttributeSyntax
    ) -> AttributeSyntax? {
        guard let leftParen = attribute.leftParen else { return nil }
        guard attribute.unexpectedBetweenLeftParenAndArguments == nil else { return nil }

        let before =
            testingDisplayNameAuthoredTrivia(leftParen.trailingTrivia)
            + testingDisplayNameAuthoredTrivia(argument.leadingTrivia)
        let after = testingDisplayNameLayoutTrivia(argument.trailingTrivia)
        let rewrittenLeftParen = leftParen.with(\.trailingTrivia, before + after)
        return
            attribute
            .with(\.leftParen, rewrittenLeftParen)
            .with(\.arguments, .argumentList(LabeledExprListSyntax(remaining)))
    }

    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        super.visit(node.with(\.attributes, fixed(name: node.name, attributes: node.attributes)))
    }

    override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        super.visit(node.with(\.attributes, fixed(name: node.name, attributes: node.attributes)))
    }

    override func visit(_ node: EnumDeclSyntax) -> DeclSyntax {
        super.visit(node.with(\.attributes, fixed(name: node.name, attributes: node.attributes)))
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        super.visit(node.with(\.attributes, fixed(name: node.name, attributes: node.attributes)))
    }

    override func visit(_ node: ActorDeclSyntax) -> DeclSyntax {
        super.visit(node.with(\.attributes, fixed(name: node.name, attributes: node.attributes)))
    }
}

/// Keeps comments and other authored trivia while discarding delimiter-only
/// whitespace that existed solely to surround the removed argument.
private func testingDisplayNameAuthoredTrivia(_ trivia: Trivia) -> Trivia {
    for piece in trivia {
        switch piece {
        case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds,
            .formfeeds, .verticalTabs:
            continue

        default:
            return trivia
        }
    }
    return []
}

/// Keeps trivia that carries a comment or a line break into the retained
/// argument. A lone separating space is rebuilt canonically as no space after
/// `(`, yielding `@Suite(.serialized)` rather than `@Suite( .serialized)`.
private func testingDisplayNameLayoutTrivia(_ trivia: Trivia) -> Trivia {
    for piece in trivia {
        switch piece {
        case .newlines, .carriageReturns, .carriageReturnLineFeeds:
            return trivia

        case .spaces, .tabs, .formfeeds, .verticalTabs:
            continue

        default:
            return trivia
        }
    }
    return []
}
