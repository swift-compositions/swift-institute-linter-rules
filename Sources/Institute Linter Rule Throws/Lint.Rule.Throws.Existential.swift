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

// swiftlint:disable no_existential_throws
// REASON: this rule's own doc comments, diagnostic message, and citation-carve-out
// prose must literally cite `throws(any Error)` — self-referential fixture shape
// (rule-exemptions skill); the regex-based no_existential_throws rule cannot
// distinguish prose citation from live code. Re-enabled after the visitor class.
/// `throws(any Error)` boxes the error existentially — semantically
/// identical to untyped `throws`. Citation: `feedback_no_existential_throws`.
extension Lint.Rule {
  public static let `existential throws` = Lint.Rule(
    id: "existential throws",
    default: .warning,
    controls: [
      .init(
        id: "existential throws any error",
        source: "func read() throws(any Error) {}",
        path: "Sources/Throws Consumer/ExistentialError.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "existential throws concrete error",
        source: "func read() throws(Read.Error) {}",
        path: "Sources/Throws Consumer/ConcreteError.swift",
        expectation: .clean
      ),
      .init(
        id: "existential throws encodable witness",
        source: "extension Value: Encodable { "
          + "func encode(to encoder: any Encoder) throws(any Error) {} }",
        path: "Sources/Throws Consumer/EncodableWitness.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      let visitor = ThrowsExistentialVisitor(
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
internal let throwsExistentialMessage: Swift.String =
  "[existential throws] feedback_no_existential_throws: `throws(any Error)` boxes "
  + "the error as an existential — semantically identical to untyped `throws`. "
  + "Use a concrete error type or make the container generic over the error type."

/// Stdlib-protocol witnesses whose untyped-throws signature is dictated
/// by the protocol requirement itself — the conformer cannot narrow the
/// throws set because downstream stdlib calls propagate `any Error`.
/// Citation key required at write time.
///
/// Gated on conformance context: the function name must match an entry
/// AND the enclosing extension's inheritance clause must name the
/// corresponding stdlib protocol. Outside that context, the same
/// signature has no structural justification and still fires.
@usableFromInline
internal let throwsExistentialStdlibProtocolWitnessCitations:
  [Swift.String: (witness: Swift.String, protocols: [Swift.String])] = [
    "init(from:)": (
      witness: "Swift.Decodable.init(from:) throws — protocol requirement is untyped",
      protocols: ["Decodable", "Codable"]
    ),
    "encode(to:)": (
      witness: "Swift.Encodable.encode(to:) throws — protocol requirement is untyped",
      protocols: ["Encodable", "Codable"]
    ),
  ]

internal final class ThrowsExistentialVisitor: SyntaxVisitor {
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

  override func visit(_ node: ThrowsClauseSyntax) -> SyntaxVisitorContinueKind {
    guard let typed = node.type else { return .visitChildren }
    guard isAnyError(typed) else { return .visitChildren }
    // Exempt per [RULE-EXEMPT-2] (protocol-witness-citation-dict):
    // walk up to the enclosing function / init decl, build the
    // witness-key string, and check whether it matches a known
    // stdlib-protocol untyped-throws requirement AND the enclosing
    // extension conforms to the corresponding stdlib protocol. The
    // protocol IS the gate — the typed-throws constraint is
    // structurally inexpressible. Tuple-valued dict form lets one
    // witness key satisfy multiple protocols (Decodable, Codable).
    // Skill: the rule-exemptions skill.
    if isStdlibProtocolWitnessThrows(Syntax(node)) {
      return .visitChildren
    }
    // Carve-out: enclosing function/init body invokes the
    // swift-testing `#require(_:)` macro. The macro's expansion is
    // `try Testing.__check(...).__required()` which throws
    // `any Error`; the enclosing function MUST be `throws(any Error)`
    // (or untyped `throws`) to propagate. No concrete public error
    // type is exposed by swift-testing for the `throws(E)` form;
    // the existential is structurally required by the macro contract.
    // See `throwsBodyContainsRequireMacro` for full rationale and
    // citation.
    if isInsideRequireMacroFunction(Syntax(node)) {
      return .visitChildren
    }
    let location = converter.location(for: typed.positionAfterSkippingLeadingTrivia)
    matches.append(
      Diagnostic.Record(
        location: Source.Location(
          fileID: source.fileID,
          filePath: source.filePath,
          line: location.line,
          column: location.column
        ),
        severity: severity,
        identifier: "existential throws",
        message: throwsExistentialMessage
      )
    )
    return .visitChildren
  }

  /// Returns true if the throws clause is on a function / init /
  /// accessor whose body invokes swift-testing's `#require(_:)` macro.
  /// The `#require` macro's expansion (`try Testing.__check(...).__required()`)
  /// throws `any Error` by macro contract — swift-testing exposes no
  /// concrete public error type for the throws clause. The enclosing
  /// function is structurally forced to `throws(any Error)` or untyped
  /// `throws` to propagate; the existential is mandated by the macro
  /// contract, not chosen by the author.
  ///
  /// Citation: feedback_no_existential_throws (rule's primary statement);
  /// 2026-05-21 binary lint remediation — dead-end documented
  /// in HANDOFF.md (typed-throws form `throws(ExpectationFailedError)`
  /// doesn't compile against swift-testing's public surface).
  private func isInsideRequireMacroFunction(_ node: Syntax) -> Swift.Bool {
    var current: Syntax? = node.parent
    while let candidate = current {
      if let fn = candidate.as(FunctionDeclSyntax.self) {
        return throwsBodyContainsRequireMacro(fn.body)
      }
      if let initDecl = candidate.as(InitializerDeclSyntax.self) {
        return throwsBodyContainsRequireMacro(initDecl.body)
      }
      if let accessor = candidate.as(AccessorDeclSyntax.self) {
        return throwsBodyContainsRequireMacro(accessor.body)
      }
      if candidate.is(StructDeclSyntax.self)
        || candidate.is(ClassDeclSyntax.self)
        || candidate.is(EnumDeclSyntax.self)
        || candidate.is(ActorDeclSyntax.self)
        || candidate.is(ExtensionDeclSyntax.self)
      {
        return false
      }
      current = candidate.parent
    }
    return false
  }

  private func throwsBodyContainsRequireMacro(_ body: CodeBlockSyntax?) -> Swift.Bool {
    guard let body else { return false }
    let finder = ThrowsExistentialRequireMacroFinder(viewMode: .sourceAccurate)
    finder.walk(body)
    return finder.found
  }

  private func isStdlibProtocolWitnessThrows(_ node: Syntax) -> Swift.Bool {
    // Walk up to the enclosing function or initializer decl, guarding both
    // branches with `witnessKey == nil` (#19 defect 2, item 1) so an OUTER
    // declaration cannot overwrite an INNER one's key — e.g. an outer
    // `init(from:)` must not clobber an inner `func helper()`'s key.
    // Accumulate every enclosing declaration's inheritance-clause leaf names
    // (item 3) rather than stopping at the innermost extension, so
    // conformance declared on the nominal TYPE itself (not just an
    // extension) is seen — matching `ThrowsUntypedVisitor`'s behavior.
    var current: Syntax? = node.parent
    var witnessKey: Swift.String?
    var witnessSignature: FunctionSignatureSyntax?
    var inheritedTypeSuffixes: Swift.Set<Swift.String> = []
    while let candidate = current {
      if witnessKey == nil {
        if let fn = candidate.as(FunctionDeclSyntax.self) {
          witnessKey = throwsWitnessKey(
            name: fn.name.text,
            parameterClause: fn.signature.parameterClause
          )
          witnessSignature = fn.signature
        } else if let initDecl = candidate.as(InitializerDeclSyntax.self) {
          witnessKey = throwsWitnessKey(
            name: "init",
            parameterClause: initDecl.signature.parameterClause
          )
          witnessSignature = initDecl.signature
        }
      }
      if let clause = throwsInheritanceClause(of: candidate) {
        for inherited in clause.inheritedTypes {
          inheritedTypeSuffixes.insert(throwsLastNameComponent(inherited.type))
        }
      }
      current = candidate.parent
    }
    guard let key = witnessKey, let signature = witnessSignature else { return false }
    // Signature-position restriction (item 2): a `throws(any Error)` inside
    // the witness BODY is not exempt — only the enclosing member's own
    // signature is conformance-forced.
    guard
      node.position >= signature.position,
      node.endPosition <= signature.endPosition
    else { return false }
    guard let entry = throwsExistentialStdlibProtocolWitnessCitations[key] else { return false }
    for protocolName in entry.protocols where inheritedTypeSuffixes.contains(protocolName) {
      return true
    }
    // Bare-extension fallback keyed off the witness key, not the protocol
    // list — the `// MARK: - Codable` pattern where the conformance is
    // declared in a separate extension/file from the witness.
    switch key {
    case "init(from:)":
      return throwsIsCanonicalWitnessSignature(
        protocolSuffix: "Decodable",
        parameters: signature.parameterClause.parameters
      )

    case "encode(to:)":
      return throwsIsCanonicalWitnessSignature(
        protocolSuffix: "Encodable",
        parameters: signature.parameterClause.parameters
      )

    default:
      return false
    }
  }

  private func throwsWitnessKey(
    name: Swift.String,
    parameterClause: FunctionParameterClauseSyntax
  )
    -> Swift.String
  {
    var key = name + "("
    for parameter in parameterClause.parameters {
      key += parameter.firstName.text + ":"
    }
    key += ")"
    return key
  }

  private func isAnyError(_ type: TypeSyntax) -> Swift.Bool {
    guard let some = type.as(SomeOrAnyTypeSyntax.self),
      some.someOrAnySpecifier.tokenKind == .keyword(.any)
    else { return false }
    return isErrorType(some.constraint)
  }

  private func isErrorType(_ type: TypeSyntax) -> Swift.Bool {
    if let identifier = type.as(IdentifierTypeSyntax.self),
      identifier.name.text == "Error"
    {
      return true
    }
    if let member = type.as(MemberTypeSyntax.self),
      member.name.text == "Error",
      let base = member.baseType.as(IdentifierTypeSyntax.self),
      base.name.text == "Swift"
    {
      return true
    }
    return false
  }
}

// swiftlint:enable no_existential_throws

/// Walks a function body looking for any `#require(_:)` macro invocation.
/// Used by `Lint.Rule.Throws.Existential`'s `#require` carve-out.
