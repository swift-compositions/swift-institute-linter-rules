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

/// The canonical fix for `[IMPL-033]`: climb the range loop to
/// `(<range>).forEach { <name> in … }`.
///
/// The fix is narrower than the finding, deliberately and permanently. A
/// `for` body is a statement context and a `forEach` body is a closure, and
/// the two differ in every construct that transfers control out of the
/// loop: `break` and `continue` have no closure spelling at all, `return`
/// returns from the closure rather than the enclosing function — silently,
/// and with the opposite meaning — and `try`, `throw`, and `await` cross a
/// `rethrows`, non-`async` boundary that erases or rejects them.
///
/// A loop containing any of those is therefore NOT autofixable, and this
/// leaves it exactly as it found it. It remains a finding, for a person to
/// resolve by restructuring rather than by translation. That is the whole
/// discipline of a rewriter-backed rule: the rewriter takes the subset it
/// can transform with certainty, and hands back the rest unchanged rather
/// than guessing. A fix that translated `return` into a `forEach` body
/// would compile and silently change what the program does, which is the
/// one outcome worse than not fixing it.
///
/// The scan is subtree-wide and does not stop at nested closures or nested
/// function declarations, where those constructs would be harmless. That
/// over-refuses, and it should: the cost of refusing a fixable loop is that
/// a person fixes it, and the cost of accepting an unfixable one is a
/// behaviour change nobody reviewed.
///
/// ## Accepted false refusals
///
/// The predicate is deliberately coarser than the truth, in four places
/// where the true test is not available to syntax. Each costs fixes on
/// loops that would have translated correctly. All four are accepted:
///
/// - **Any loop lexically inside a closure.** Whether a closure is a result
///   builder body is decided by an attribute on the parameter it is passed
///   to, which lives in another file. So `xs.map { … }`, `Task { … }`,
///   `withLock { … }`, and every other plainly-a-function-value closure
///   keeps its loops unfixed, alongside the `VStack { … }` bodies this is
///   actually aimed at. The earlier carve-out for closures with a parameter
///   signature was unsound and is gone: a builder parameter may be a
///   function type taking arguments.
/// - **Any loop under a declaration returning `some …`, or carrying an
///   attribute whose name ends in `Builder`.** Both are name-shaped
///   evidence, and a `@ConfigurationBuilder` that is not a result builder
///   refuses for nothing.
/// - **Any loop with a comment in a position the rewrite rebuilds.** See
///   ``idiomIterationIntentDropsComments(_:)``: a documented loop header is
///   left alone rather than have its comment deleted.
/// - **Any loop whose body mentions a name that matches a `borrowing`/
///   `consuming` parameter of the enclosing declaration, even one shadowed
///   by a same-named local.** See
///   ``idiomIterationIntentReferencesOwnershipAnnotatedBinding(_:)``: the
///   match is by name, not by resolving the binding, because the parameter
///   set considered is exactly the enclosing signature and nothing beyond
///   it is guessed at.
///
/// A refused-but-safe loop stays a finding, which is a person reading one
/// line. A fixed-but-broken loop is a silent behaviour change in a commit
/// nobody looked at. The asymmetry is the whole argument.
internal func idiomIterationIntentFixed(
    _ source: borrowing Lint.Source.Parsed
) -> Swift.String? {
    let rewriter = IdiomIterationIntentRewriter()
    let rewritten = rewriter.visit(source.tree)
    guard rewriter.changed else { return nil }
    return rewritten.description
}

/// Whether `loop` may be translated to `forEach` without changing meaning.
///
/// Mirrors the detector's own guards first — the fix must never fire where
/// the finding does not — and then applies the closure-boundary
/// restrictions the detector has no reason to know about.
internal func idiomIterationIntentIsFixable(_ loop: ForStmtSyntax) -> Swift.Bool {
    guard loop.pattern.is(IdentifierPatternSyntax.self) else { return false }
    guard idiomIsRangeExpression(loop.sequence) else { return false }
    guard !idiomLoopPreservesTypedThrows(loop) else { return false }
    // A `where` clause is a filter, and a type annotation is an explicit
    // parameter type. Both are expressible in a closure, and neither is
    // expressible without deciding how — so neither is translated here.
    guard loop.whereClause == nil, loop.typeAnnotation == nil else { return false }
    // A labelled loop's label can only be the target of a `break`/`continue`
    // that names it, and neither survives the translation.
    guard loop.parent?.as(LabeledStmtSyntax.self) == nil else { return false }
    guard !idiomIterationIntentProducesContent(loop) else { return false }
    guard !idiomIterationIntentDropsComments(loop) else { return false }
    guard !idiomIterationIntentReferencesOwnershipAnnotatedBinding(loop) else { return false }
    return !idiomIterationIntentBodyEscapes(Syntax(loop.body))
}

/// Whether `loop`'s body references a `borrowing` or `consuming` parameter
/// of its nearest enclosing function, initializer, or subscript.
///
/// A `borrowing`/`consuming` parameter is guaranteed not to escape the
/// activation frame that declares it. The `forEach` translation moves the
/// loop's own statements into a closure — a distinct activation frame — and
/// referencing the parameter there does not compile: witnessed at
/// swift-affine-geometry PR #5, `error: 'rhs' is borrowed and
/// cannot be consumed` on exactly this rewrite. This shape parses cleanly
/// and fails only at type checking, so the structural repair must refuse it.
///
/// Resolution is by NAME, not by full binding resolution — the same
/// technique ``MemoryBorrowingSelfShortCircuitFinder`` uses for borrowing
/// `self`. Syntax alone cannot tell whether a body identifier shadows the
/// parameter with a same-named local, so a shadowed reference over-refuses.
/// That costs a fix, never a broken program, and matches this file's
/// standing asymmetry (see the type doc above): the parameter set considered
/// is exactly the enclosing declaration's own signature, so the predicate
/// never runs unresolvable full-program name lookup and never refuses a
/// loop for a name it cannot explain.
private func idiomIterationIntentReferencesOwnershipAnnotatedBinding(
    _ loop: ForStmtSyntax
) -> Swift.Bool {
    let names = idiomEnclosingOwnershipAnnotatedParameterNames(Syntax(loop))
    guard !names.isEmpty else { return false }
    return idiomSubtreeReferencesAnyName(names, in: Syntax(loop.body))
}

/// The `borrowing`/`consuming` parameter names declared by the nearest
/// enclosing function, initializer, or subscript.
///
/// The climb stops at the first such declaration — the narrowest activation
/// frame the `forEach` closure escapes. A loop reaching this guard cannot be
/// nested inside a closure: ``idiomIterationIntentProducesContent`` already
/// refused any loop under a ``ClosureExprSyntax``, so the climb never needs
/// to cross one and never needs to decide what a closure parameter's
/// ownership would mean.
private func idiomEnclosingOwnershipAnnotatedParameterNames(
    _ node: Syntax
) -> Swift.Set<Swift.String> {
    var current: Syntax? = node.parent
    while let candidate = current {
        if let function = candidate.as(FunctionDeclSyntax.self) {
            return idiomOwnershipAnnotatedParameterNames(
                function.signature.parameterClause.parameters
            )
        }
        if let initializer = candidate.as(InitializerDeclSyntax.self) {
            return idiomOwnershipAnnotatedParameterNames(
                initializer.signature.parameterClause.parameters
            )
        }
        if let subscriptDecl = candidate.as(SubscriptDeclSyntax.self) {
            return idiomOwnershipAnnotatedParameterNames(subscriptDecl.parameterClause.parameters)
        }
        current = candidate.parent
    }
    return []
}

/// The local (body-visible) names of every parameter in `parameters` whose
/// type carries an explicit `borrowing` or `consuming` specifier.
private func idiomOwnershipAnnotatedParameterNames(
    _ parameters: FunctionParameterListSyntax
) -> Swift.Set<Swift.String> {
    var names: Swift.Set<Swift.String> = []
    for parameter in parameters {
        guard let attributed = parameter.type.as(AttributedTypeSyntax.self) else { continue }
        for specifier in attributed.specifiers {
            guard let simple = specifier.as(SimpleTypeSpecifierSyntax.self) else { continue }
            let kind = simple.specifier.tokenKind
            guard kind == .keyword(.borrowing) || kind == .keyword(.consuming) else { continue }
            names.insert((parameter.secondName ?? parameter.firstName).text)
            break
        }
    }
    return names
}

/// Whether `node`'s subtree references any identifier in `names`.
///
/// A nested closure or local function declaration is its own activation
/// frame both before and after this rewrite — the `forEach` translation
/// does not change whether IT can capture an outer ownership-annotated
/// parameter, so a reference confined to one is not this guard's concern
/// and the walk does not descend into it.
private func idiomSubtreeReferencesAnyName(
    _ names: Swift.Set<Swift.String>,
    in node: Syntax
) -> Swift.Bool {
    if node.is(ClosureExprSyntax.self) { return false }
    if node.is(FunctionDeclSyntax.self) { return false }
    if let reference = node.as(DeclReferenceExprSyntax.self) {
        return names.contains(reference.baseName.text)
    }
    for child in node.children(viewMode: .sourceAccurate) {
        if idiomSubtreeReferencesAnyName(names, in: child) { return true }
    }
    return false
}

/// Whether translating `loop` would discard a comment.
///
/// The `forEach` spelling keeps the loop's own leading trivia, its body
/// statements, and its closing brace, and SYNTHESIZES everything in between:
/// the `in` keyword, the parameter name, and the spacing around the receiver
/// are built fresh. Whitespace there is reconstructed on purpose. A comment
/// there is not reconstructible — `for i in 0 ..< 10 /* overflow guard */ {`
/// and `for /* index into table */ j in 0..<5 {` both lose their comment
/// with no diagnostic, and a fix that silently deletes what a person wrote
/// is not a fix. There is no obviously right place to reattach either one,
/// so the loop stays a finding.
private func idiomIterationIntentDropsComments(_ loop: ForStmtSyntax) -> Swift.Bool {
    let dropped: [Trivia] = [
        loop.forKeyword.trailingTrivia,
        loop.pattern.leadingTrivia,
        loop.pattern.trailingTrivia,
        loop.inKeyword.leadingTrivia,
        loop.inKeyword.trailingTrivia,
        loop.sequence.leadingTrivia,
        loop.sequence.trailingTrivia,
        loop.body.leftBrace.leadingTrivia,
    ]
    return dropped.contains(where: idiomTriviaHasComment)
}

/// Whether `trivia` holds anything a person wrote — that is, anything but
/// whitespace.
///
/// Named for the case that matters. Every non-comment piece a rewritten
/// position can carry is whitespace the fix rebuilds, and the default arm
/// answers `true` so that a trivia kind this rule has never seen refuses
/// rather than gets deleted.
private func idiomTriviaHasComment(_ trivia: Trivia) -> Swift.Bool {
    for piece in trivia {
        switch piece {
        case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds,
            .formfeeds, .verticalTabs:
            continue

        default:
            return true
        }
    }
    return false
}

/// Whether `loop` sits in a body whose statements PRODUCE a value rather
/// than only perform effects — a `@resultBuilder`-applied body.
///
/// This is the second half of the closure-boundary problem, and the more
/// dangerous half. The guards above concern control TRANSFER, where the
/// translated program still compiles and merely means something else. Here
/// the loop's own result is the payload: under a result builder a `for-in`
/// lowers to `buildArray` and contributes content, while `forEach` returns
/// `Void` and discards it. The rewritten body then fails to compile, or —
/// worse, where the builder accepts `Void` — silently renders nothing.
///
/// Syntax cannot see a builder attribute that lives on the PARAMETER a
/// closure is passed to, so this refuses wherever it cannot prove the
/// context is a plain one, per the rule for any guard whose false-negative
/// changes behaviour. The climb stops at the nearest declaration or closure
/// boundary, because a builder attribute on an outer declaration says
/// nothing about a plain closure nested inside it.
private func idiomIterationIntentProducesContent(_ loop: ForStmtSyntax) -> Swift.Bool {
    var node: Syntax? = Syntax(loop).parent
    while let current = node {
        // A closure is a boundary, and ANY closure may be a builder body: the
        // attribute lives on the parameter the closure is passed to, in another
        // file, and no amount of local syntax can rule that out —
        // `PDF.Stack(…) { … }` and `VStack { … }` are exactly this shape.
        //
        // A parameter signature does NOT prove otherwise. A result-builder
        // parameter is an ordinary function type and may take arguments:
        // `init(@ListBuilder content: (Int) -> [String])` is called
        // `Reader { proxy in … }`, and a builder that accepts `Void` — every
        // builder with a `buildExpression(_: Void)` overload, and the
        // geometry-proxy shape generally — swallows the rewritten `forEach`
        // and renders nothing where the loop produced content. That compiles.
        // Nothing catches it.
        if current.is(ClosureExprSyntax.self) { return true }
        // A declaration is a boundary. It is a builder body when it carries a
        // builder attribute, or when its result is opaque — `var body: some
        // View` infers `@ViewBuilder` from the protocol without spelling it,
        // and the syntax of the declaration is all this rule ever sees.
        if let attributes = idiomDeclarationAttributes(current) {
            return idiomAttributesNameABuilder(attributes)
                || idiomDeclarationResultIsOpaque(current)
        }
        node = current.parent
    }
    return false
}

/// The attribute list of `node` when `node` is a declaration that can own a
/// body, and `nil` for every other node.
private func idiomDeclarationAttributes(_ node: Syntax) -> AttributeListSyntax? {
    if let decl = node.as(FunctionDeclSyntax.self) { return decl.attributes }
    if let decl = node.as(InitializerDeclSyntax.self) { return decl.attributes }
    if let decl = node.as(SubscriptDeclSyntax.self) { return decl.attributes }
    if let decl = node.as(VariableDeclSyntax.self) { return decl.attributes }
    if let decl = node.as(AccessorDeclSyntax.self) { return decl.attributes }
    return nil
}

/// Whether any attribute in `attributes` names a result builder.
///
/// A result builder is recognised by its name, because the declaration of
/// the attribute lives in another module and a linter reads one file. Every
/// result builder in the language and its libraries is named for what it
/// builds and ends in `Builder` — `@ViewBuilder`, `@SceneBuilder`,
/// `@RegexComponentBuilder` — and a plain attribute that happens to end the
/// same way costs a refused fix, not a broken program.
private func idiomAttributesNameABuilder(_ attributes: AttributeListSyntax) -> Swift.Bool {
    for element in attributes {
        guard case .attribute(let attribute) = element else { continue }
        let name = attribute.attributeName.trimmedDescription
        let simple = name.split(separator: ".").last.map(Swift.String.init) ?? name
        if simple.hasSuffix("Builder") { return true }
    }
    return false
}

/// Whether the declaration's stated result type is opaque.
private func idiomDeclarationResultIsOpaque(_ node: Syntax) -> Swift.Bool {
    if let decl = node.as(FunctionDeclSyntax.self) {
        return idiomTypeIsOpaque(decl.signature.returnClause?.type)
    }
    if let decl = node.as(SubscriptDeclSyntax.self) {
        return idiomTypeIsOpaque(decl.returnClause.type)
    }
    if let decl = node.as(VariableDeclSyntax.self) {
        for binding in decl.bindings where idiomTypeIsOpaque(binding.typeAnnotation?.type) {
            return true
        }
        return false
    }
    if let decl = node.as(AccessorDeclSyntax.self) {
        // An accessor's result is its property's, which is three levels up:
        // accessor, accessor list, accessor block, binding.
        let property = decl.parent?.parent?.parent?.as(PatternBindingSyntax.self)
        return idiomTypeIsOpaque(property?.typeAnnotation?.type)
    }
    return false
}

/// Whether `type` is spelled `some …`.
///
/// `any …` is excluded deliberately. An existential result is an ordinary
/// return type that no protocol turns into a builder body, and refusing it
/// would cost fixes for nothing.
private func idiomTypeIsOpaque(_ type: TypeSyntax?) -> Swift.Bool {
    guard let type = type?.as(SomeOrAnyTypeSyntax.self) else { return false }
    return type.someOrAnySpecifier.tokenKind == .keyword(.some)
}

/// Whether `node`'s subtree holds any construct whose meaning differs
/// inside a closure.
private func idiomIterationIntentBodyEscapes(_ node: Syntax) -> Swift.Bool {
    if node.is(BreakStmtSyntax.self) { return true }
    if node.is(ContinueStmtSyntax.self) { return true }
    if node.is(ReturnStmtSyntax.self) { return true }
    if node.is(ThrowStmtSyntax.self) { return true }
    if node.is(TryExprSyntax.self) { return true }
    if node.is(AwaitExprSyntax.self) { return true }
    // A `yield` in an accessor, likewise: it belongs to the accessor, not to
    // whatever closure it is nested in.
    if node.is(YieldStmtSyntax.self) { return true }
    for child in node.children(viewMode: .sourceAccurate) {
        if idiomIterationIntentBodyEscapes(child) { return true }
    }
    return false
}

/// Builds `(<sequence>).forEach { <name> in <body> }` for a fixable loop.
internal func idiomIterationIntentCall(for loop: ForStmtSyntax) -> ExprSyntax? {
    guard let pattern = loop.pattern.as(IdentifierPatternSyntax.self) else { return nil }

    // A bare range is parenthesized so `.forEach` binds to the range rather
    // than to its upper bound. A sequence that is already a call —
    // `(a..<b).reversed()` — needs no second pair, and adding one would make
    // every fixed line noisier than the rule that asked for it.
    let receiver: ExprSyntax
    let bare = loop.sequence.with(\.leadingTrivia, []).with(\.trailingTrivia, [])
    if bare.is(SequenceExprSyntax.self) || bare.is(InfixOperatorExprSyntax.self) {
        receiver = ExprSyntax(
            TupleExprSyntax(
                elements: LabeledExprListSyntax([LabeledExprSyntax(expression: bare)])
            )
        )
    } else {
        receiver = bare
    }

    // The whitespace between the loop's `{` and its first statement is
    // attached to whichever token owns it: everything up to the end of the
    // line is the brace's TRAILING trivia, and the rest is the statement's
    // leading trivia. So a single-line body `{ sum += i }` keeps its only
    // space on the brace, and moving the statements alone would emit
    // `{ i insum += i }`. The `in` keyword inherits that trivia, and
    // supplies a space itself only when neither side has any — the
    // multi-line case must NOT gain one, or every fixed loop would carry a
    // trailing space before its newline.
    let braceTrailing = loop.body.leftBrace.trailingTrivia
    let firstLeading = loop.body.statements.first?.leadingTrivia ?? []
    let inTrailing: Trivia =
        braceTrailing.isEmpty && firstLeading.isEmpty ? .space : braceTrailing
    let closure = ClosureExprSyntax(
        leftBrace: .leftBraceToken(leadingTrivia: .space),
        signature: ClosureSignatureSyntax(
            parameterClause: .simpleInput(
                ClosureShorthandParameterListSyntax([
                    ClosureShorthandParameterSyntax(
                        name: pattern.identifier.with(\.leadingTrivia, .space).with(
                            \.trailingTrivia,
                            []
                        )
                    )
                ])
            ),
            inKeyword: .keyword(.in, leadingTrivia: .space, trailingTrivia: inTrailing)
        ),
        statements: loop.body.statements,
        rightBrace: loop.body.rightBrace.with(\.leadingTrivia, loop.body.rightBrace.leadingTrivia)
    )

    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(
            MemberAccessExprSyntax(base: receiver, name: .identifier("forEach"))
        ),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )
    return ExprSyntax(call)
        .with(\.leadingTrivia, loop.leadingTrivia)
        .with(\.trailingTrivia, loop.trailingTrivia)
}

/// Replaces each fixable range loop with its `forEach` spelling.
///
/// The swap happens at ``CodeBlockItemSyntax`` rather than at
/// ``ForStmtSyntax`` because the replacement is an expression where the
/// original was a statement, and only the item knows how to hold either.
internal final class IdiomIterationIntentRewriter: SyntaxRewriter {
    var changed: Swift.Bool = false

    override func visit(_ node: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
        guard case .stmt(let statement) = node.item,
            let loop = statement.as(ForStmtSyntax.self),
            idiomIterationIntentIsFixable(loop),
            let call = idiomIterationIntentCall(for: loop)
        else {
            return super.visit(node)
        }
        changed = true
        // The rewritten item is re-visited so a nested fixable loop inside the
        // body climbs too, in the same pass.
        return super.visit(node.with(\.item, .expr(call)))
    }
}
