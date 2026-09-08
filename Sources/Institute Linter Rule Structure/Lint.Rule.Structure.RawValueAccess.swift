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

/// Wave 4 (mechanization-program) — `.rawValue` accesses
/// at consumer call sites bypass typed-conversion ladders.
///
/// Citation: `[PATTERN-017]` (implementation skill, the patterns note).
///
/// ## Same-package implementation sites — ruled disposition
///
/// Ruled 2026-08-01 (#38, from the 2026-08-01 fleet sweep): the message
/// has always reserved these accessors for the brand's own initializers
/// AND same-package implementations, but only the first clause was
/// mechanized. The second clause is mechanized here for the ONE shape with
/// a stable syntactic property — the receiver is the enclosing type's own
/// instance, spelled either `self` or a parameter of the directly
/// enclosing function whose WRITTEN type is `Self` or the enclosing type's
/// own name. Both are syntax present at the site, in the same way the
/// initializer reserve and the Foundation-import gate elsewhere are.
///
/// Every other same-package implementation is **accept-as-warning**, not a
/// predicate exemption (the [IMPL-089] precedent): a local `let` bound
/// from a foreign brand, or a parameter written as a typealias of the
/// enclosing type, cannot be told apart from a genuine consumer call site
/// without a type checker. Widening on the file's path, the module name,
/// or a comment would be a path/name exemption in disguise. The engine's
/// per-site `// swift-linter:disable:next raw value access` with a
/// `// REASON:` continuation is the correct instrument there.
extension Lint.Rule {
  public static let `raw value access` = Lint.Rule(
    id: "raw value access",
    default: .warning,
    controls: [
      .init(
        id: "raw value access consumer",
        source: "func value(_ tag: Tag) -> Int { tag.rawValue }",
        path: "Sources/Structure Core/Consumer.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "raw value access initializer boundary",
        source: "struct Wrapper { init(_ tag: Tag) { _ = tag.rawValue } }",
        path: "Sources/Structure Core/Wrapper.swift",
        expectation: .clean
      ),
      .init(
        id: "raw value access enclosing self",
        source: "struct Tag { func value() -> Int { self.rawValue } }",
        path: "Sources/Structure Core/Tag.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // §A brand-owner recognizer: when the run's own sources declare a
      // numeric brand, same-package `.rawValue` boundary access is
      // legitimate-by-construction. Retires the per-package
      // `.excluding(rules:)` stopgap ([LINT-EXCLUDE-*]).
      if Lint.Brand.owned(Lint.Brand.vocabulary, in: source) { return [] }
      let visitor = StructureRawValueAccessVisitor(
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
internal let structureRawValueAccessMessage: Swift.String =
  "[raw value access] [PATTERN-017]: `.rawValue` at a "
  + "consumer call site bypasses the typed-conversion ladder. These "
  + "accessors are reserved for the brand-newtype's own initializers — "
  + "the typed-conversion boundary the ladder terminates in — and "
  + "same-package implementations. Only the directly enclosing "
  + "initializer counts; a closure or nested function inside an "
  + "initializer is ordinary consumer code and still fires. Prefer the "
  + "typed operation. Same-package implementation sites do NOT fire when "
  + "the receiver is the enclosing type's own instance — `self.rawValue`, "
  + "or a parameter written `Self` / the enclosing type's own name (the "
  + "brand's own operators and serializers). A stored member of `self` "
  + "(`self.tag.rawValue`) is a foreign brand and still fires. "
  + "**Accept-as-warning** disposition (rule fires legitimately, leave "
  + "the warning): a same-package implementation whose receiver is "
  + "neither of those two spellings — a local `let` bound from a foreign "
  + "brand, or a parameter written as a typealias of the enclosing type. "
  + "Whether two written names denote one type is type-checker knowledge, "
  + "not syntax; the warning is the review signal. "
  + "Suppress with "
  + "`// swift-linter:disable:next raw value access` and a `// REASON:` "
  + "continuation for legitimate same-package use."

internal let structureRawValueAccessFlaggedAccessors: Swift.Set<Swift.String> = ["rawValue"]

/// The parameter named `name` on the function-like declaration that most
/// directly encloses `node`, or `nil` when the nearest enclosing
/// function-like context declares no such parameter. The search stops at
/// the FIRST function-like ancestor, so a closure's captured outer
/// parameter does not qualify.
internal func structureEnclosingParameter(
  named name: Swift.String,
  at node: Syntax
) -> FunctionParameterSyntax? {
  var current: Syntax? = node.parent
  while let candidate = current {
    if candidate.is(ClosureExprSyntax.self) { return nil }
    var parameters: FunctionParameterListSyntax?
    if let function = candidate.as(FunctionDeclSyntax.self) {
      parameters = function.signature.parameterClause.parameters
    } else if let initializer = candidate.as(InitializerDeclSyntax.self) {
      parameters = initializer.signature.parameterClause.parameters
    } else if let subscriptDecl = candidate.as(SubscriptDeclSyntax.self) {
      parameters = subscriptDecl.parameterClause.parameters
    }
    if let parameters {
      for parameter in parameters
      where (parameter.secondName ?? parameter.firstName).text == name {
        return parameter
      }
      return nil
    }
    current = candidate.parent
  }
  return nil
}

/// The written type name of a parameter, with ownership specifiers,
/// attributes, optionality, and module qualification stripped —
/// `borrowing Self` → `Self`, `Cardinal.Value?` → `Value`.
internal func structureNormalizedTypeName(_ type: TypeSyntax) -> Swift.String {
  var current = type
  while true {
    if let attributed = current.as(AttributedTypeSyntax.self) {
      current = attributed.baseType
      continue
    }
    if let optional = current.as(OptionalTypeSyntax.self) {
      current = optional.wrappedType
      continue
    }
    if let implicit = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      current = implicit.wrappedType
      continue
    }
    break
  }
  if let member = current.as(MemberTypeSyntax.self) { return member.name.text }
  if let identifier = current.as(IdentifierTypeSyntax.self) { return identifier.name.text }
  return current.trimmedDescription
}

/// Every type name that lexically encloses `node` — nominal declarations by
/// their own name, extensions by their extended type's last component.
internal func structureEnclosingTypeNames(at node: Syntax) -> Swift.Set<Swift.String> {
  var names: Swift.Set<Swift.String> = []
  var current: Syntax? = node.parent
  while let candidate = current {
    if let structDecl = candidate.as(StructDeclSyntax.self) {
      names.insert(structDecl.name.text)
    }
    if let classDecl = candidate.as(ClassDeclSyntax.self) { names.insert(classDecl.name.text) }
    if let enumDecl = candidate.as(EnumDeclSyntax.self) { names.insert(enumDecl.name.text) }
    if let actorDecl = candidate.as(ActorDeclSyntax.self) { names.insert(actorDecl.name.text) }
    if let extensionDecl = candidate.as(ExtensionDeclSyntax.self) {
      names.insert(structureNormalizedTypeName(extensionDecl.extendedType))
    }
    current = candidate.parent
  }
  return names
}

internal final class StructureRawValueAccessVisitor: SyntaxVisitor {
  let source: Source.File
  let severity: Diagnostic.Severity
  let converter: SourceLocationConverter
  var matches: [Diagnostic.Record] = []
  var bodyDepth: Swift.Int = 0

  init(
    source: Source.File,
    severity: Diagnostic.Severity,
    converter: SourceLocationConverter
  ) {
    self.source = source
    self.severity = severity
    self.converter = converter
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    bodyDepth += 1
    return .visitChildren
  }
  override func visitPost(_: FunctionDeclSyntax) {
    bodyDepth -= 1
  }
  override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    bodyDepth += 1
    return .visitChildren
  }
  override func visitPost(_: InitializerDeclSyntax) {
    bodyDepth -= 1
  }
  // #28 nit 2: `deinit { x.rawValue }` was previously invisible to
  // this rule — nothing bumped `bodyDepth` for a `DeinitializerDeclSyntax`
  // body, so the `guard bodyDepth > 0` in the member-access visit
  // below short-circuited before `isDirectlyInsideInitializer`'s
  // `Deinitializer` walk-stopper guard was ever reached. The ruled
  // fixture (`deinit { x.rawValue }` → 1 finding) requires this bump
  // to exist at all.
  override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    bodyDepth += 1
    return .visitChildren
  }
  override func visitPost(_: DeinitializerDeclSyntax) {
    bodyDepth -= 1
  }
  override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
    bodyDepth += 1
    return .visitChildren
  }
  override func visitPost(_: ClosureExprSyntax) {
    bodyDepth -= 1
  }
  override func visit(_: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
    bodyDepth += 1
    return .visitChildren
  }
  override func visitPost(_: AccessorDeclSyntax) {
    bodyDepth -= 1
  }
  override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
    // A short-form getter (`var x: Int { tag.rawValue }`) parses as
    // `.getter`, with no `AccessorDeclSyntax` at all — the override above
    // never fires for it. Without this, `.rawValue` access inside a
    // shorthand computed property or subscript getter silently escapes
    // the rule.
    if structureIsShorthandGetterAccessorBlock(Syntax(node)) {
      bodyDepth += 1
    }
    return .visitChildren
  }
  override func visitPost(_ node: AccessorBlockSyntax) {
    if structureIsShorthandGetterAccessorBlock(Syntax(node)) {
      bodyDepth -= 1
    }
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    guard bodyDepth > 0 else { return .visitChildren }
    let name = node.declName.baseName.text
    guard structureRawValueAccessFlaggedAccessors.contains(name) else {
      return .visitChildren
    }
    // Initializer-boundary reserve (#16 Option C ledger, Entry II.1 DECISION
    // 2026-07-23): the rule's own message reserves these accessors for
    // "extension initializers (the brand-newtype's own boundary)" — an
    // initializer IS the typed-conversion boundary the ladder terminates in
    // (`init(rawValue:)` assigning its stored raw value; an adapter init
    // consuming the brand's raw form exactly once). The implementation
    // previously fired there anyway (e.g. `self.rawValue = rawValue` inside
    // the declaring `init(rawValue:)`, swift-iso-9945
    // `ISO 9945.Kernel.Process.ID.swift`), contradicting the message text.
    // Only the DIRECTLY enclosing function-like context counts: a closure or
    // nested function inside an initializer is ordinary consumer code and
    // still fires.
    if isDirectlyInsideInitializer(Syntax(node)) {
      return .visitChildren
    }
    // Disambiguate Swift.enum.rawValue from Tagged-newtype rawValue
    // via receiver-pattern recognition: `Lint.Visibility.public.rawValue`
    // looks like `<TypeChain>.<member>.rawValue`, where TypeChain is
    // one or more uppercase-leading identifier segments. Skip those —
    // they are `RawRepresentable.rawValue` access, outside the rule's
    // Tagged-newtype-targeting scope. The known false-negative on
    // `Module.staticTagInstance.rawValue` is accepted (uncommon for
    // Tagged consumer access). See the 2026-05-12 foundation-up dogfeed triage note
    // §A2 for the architectural rationale.
    if let receiver = node.base, receiverLooksLikeEnumCaseAccess(receiver) {
      return .visitChildren
    }
    // Same-package implementation-site reserve (#38, sourced from the
    // 2026-08-01 fleet sweep). The rule's own message reserves these
    // accessors for "the brand-newtype's own initializers … and
    // same-package implementations". The initializer arm above honors the
    // first clause; this arm honors the second, for the ONE shape with a
    // stable syntactic property: the receiver is the enclosing type's own
    // instance.
    //
    // Two spellings qualify, and only these two:
    //  1. `self.rawValue` — `self` can only denote the
    //     directly enclosing declaration's own type, so the file that
    //     contains the access also contains the declaration. There is no
    //     foreign brand and no ladder to bypass.
    //  2. `lhs.rawValue` where `lhs` is a parameter of the directly
    //     enclosing function whose WRITTEN type is `Self` or the enclosing
    //     type's own name — the brand's own operators, serializers, and
    //     comparators (`static func + (lhs: Self, rhs: Self)`). The
    //     parameter's type annotation is syntax, present at the site.
    //
    // Anything else still fires, including `self.tag.rawValue` (the
    // receiver is a STORED MEMBER of `self`, i.e. a foreign brand held by
    // this type, not this type's own raw form) and any parameter whose
    // written type is some other brand.
    if let receiver = node.base, receiverIsEnclosingTypeInstance(receiver, at: Syntax(node)) {
      return .visitChildren
    }
    let location = converter.location(
      for: node.declName.baseName.positionAfterSkippingLeadingTrivia
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
        identifier: "raw value access",
        message: structureRawValueAccessMessage
      )
    )
    return .visitChildren
  }

  /// True when the nearest enclosing function-like context of `node` is an
  /// `InitializerDeclSyntax` — the typed-conversion boundary the rule's
  /// message reserves. The walk stops at the FIRST function-like ancestor
  /// (function, accessor, or closure), so raw access inside a closure or
  /// helper nested within an init is not exempt.
  private func isDirectlyInsideInitializer(_ node: Syntax) -> Swift.Bool {
    var current: Syntax? = node.parent
    while let candidate = current {
      if candidate.is(InitializerDeclSyntax.self) { return true }
      if candidate.is(FunctionDeclSyntax.self)
        || candidate.is(AccessorDeclSyntax.self)
        || structureIsShorthandGetterAccessorBlock(candidate)
        || candidate.is(ClosureExprSyntax.self)
        || candidate.is(DeinitializerDeclSyntax.self)
        || candidate.is(SubscriptDeclSyntax.self)
      {
        return false
      }
      current = candidate.parent
    }
    return false
  }

  /// True when `receiver` denotes an instance of the type that lexically
  /// encloses `node` — either the `self` keyword, or a parameter of the
  /// directly enclosing function whose written type is `Self` or the
  /// enclosing type's own name. See the same-package implementation-site
  /// reserve in `visit(_: MemberAccessExprSyntax)`.
  private func receiverIsEnclosingTypeInstance(
    _ receiver: ExprSyntax,
    at node: Syntax
  ) -> Swift.Bool {
    guard let reference = receiver.as(DeclReferenceExprSyntax.self) else { return false }
    let name = reference.baseName.text
    if name == "self" { return true }
    guard let parameter = structureEnclosingParameter(named: name, at: node) else {
      return false
    }
    let written = structureNormalizedTypeName(parameter.type)
    if written == "Self" { return true }
    return structureEnclosingTypeNames(at: node).contains(written)
  }

  /// True if `base` parses as `<TypeChain>.<member>` — i.e. an enum
  /// case access shape (`Foo.bar`, `Lint.Visibility.public`) rather
  /// than a Tagged-newtype instance access (`tag`, `self.tag`).
  private func receiverLooksLikeEnumCaseAccess(_ base: ExprSyntax) -> Swift.Bool {
    guard let caseAccess = base.as(MemberAccessExprSyntax.self),
      let typeBase = caseAccess.base
    else { return false }
    return isTypeChain(typeBase)
  }

  /// True if `expr` is one or more uppercase-leading identifier
  /// segments joined by `.` — i.e. a type qualifier like `Lint`,
  /// `Lint.Visibility`, or `Module.Sub.Type`. Lowercase-leading
  /// segments (instance refs like `self`, `tag`) return false.
  private func isTypeChain(_ expr: ExprSyntax) -> Swift.Bool {
    if let ref = expr.as(DeclReferenceExprSyntax.self) {
      return ref.baseName.text.first?.isUppercase ?? false
    }
    if let member = expr.as(MemberAccessExprSyntax.self),
      let base = member.base
    {
      return isTypeChain(base)
        && (member.declName.baseName.text.first?.isUppercase ?? false)
    }
    return false
  }
}
