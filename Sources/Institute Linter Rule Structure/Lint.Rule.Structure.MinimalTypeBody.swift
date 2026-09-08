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

/// Wave 3 (mechanization-program) — type declarations MUST contain only
/// stored properties, the canonical initializer, and (for class /
/// ~Copyable types) `deinit`. All other members MUST be in extensions.
///
/// Citation: `[API-IMPL-008]` (code-surface skill — minimal type body).
extension Lint.Rule {
  public static let `minimal type body` = Lint.Rule(
    id: "minimal type body",
    default: .warning,
    controls: [
      .init(
        id: "minimal type body method",
        source: "struct Value { func read() -> Int { 0 } }",
        path: "Sources/Structure Core/Value.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "minimal type body storage and initializer",
        source: "struct Value { let raw: Int; init(raw: Int) { self.raw = raw } }",
        path: "Sources/Structure Core/Value.swift",
        expectation: .clean
      ),
      .init(
        id: "minimal type body extension method",
        source: "extension Value { func read() -> Int { 0 } }",
        path: "Sources/Structure Core/Value+Read.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      let visitor = StructureMinimalTypeBodyVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    },
    repair: { source in
      guard let contents = structureMinimalTypeBodyFixed(source) else { return .unchanged }
      return .edits([.rewrite(path: source.path, contents: contents)])
    }
  )
}

@usableFromInline
internal let structureMinimalTypeBodyMessage: Swift.String =
  "[minimal type body] [API-IMPL-008]: type bodies MUST contain "
  + "ONLY stored properties, the canonical initializer(s), and "
  + "(for classes / ~Copyable types) `deinit`. Methods, computed "
  + "properties, static members, nested types, and protocol "
  + "conformances belong in extensions. Minimal bodies make storage "
  + "layout immediately visible and separate stable data from "
  + "evolving behavior."

internal func structureMinimalTypeBodyIsComputedProperty(_ node: VariableDeclSyntax) -> Swift.Bool {
  for binding in node.bindings {
    if let accessors = binding.accessorBlock {
      switch accessors.accessors {
      case .accessors(let accessorList):
        for accessor in accessorList {
          switch accessor.accessorSpecifier.tokenKind {
          case .keyword(.get), .keyword(.set),
            .keyword(._read), .keyword(._modify):
            return true

          default:
            continue
          }
        }

      case .getter:
        return true
      }
    }
  }
  return false
}

internal func structureMinimalTypeBodyIsStaticOrClassMember(
  _ modifiers: DeclModifierListSyntax
)
  -> Swift.Bool
{
  for modifier in modifiers {
    switch modifier.name.tokenKind {
    case .keyword(.static), .keyword(.class):
      return true

    default:
      continue
    }
  }
  return false
}

internal final class StructureMinimalTypeBodyVisitor: SyntaxVisitor {
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

  private func emit(at position: AbsolutePosition) {
    let location = converter.location(for: position)
    matches.append(
      Diagnostic.Record(
        location: Source.Location(
          fileID: source.fileID,
          filePath: source.filePath,
          line: location.line,
          column: location.column
        ),
        severity: severity,
        identifier: "minimal type body",
        message: structureMinimalTypeBodyMessage
      )
    )
  }

  private func checkMembers(_ block: MemberBlockSyntax) {
    // #28 defect 2: enumerating `block.members` by hand drops every
    // `#if`-guarded member. `Lint.Syntax.Conditional.members(_:)` splices
    // each clause's members in recursively so a platform-conditional
    // member is checked exactly as an unguarded one would be.
    for member in Lint.Syntax.Conditional.members(block) {
      let decl = member.decl
      if let variable = decl.as(VariableDeclSyntax.self) {
        if structureMinimalTypeBodyIsStaticOrClassMember(variable.modifiers) {
          emit(at: variable.bindingSpecifier.positionAfterSkippingLeadingTrivia)
        } else if structureMinimalTypeBodyIsComputedProperty(variable) {
          emit(at: variable.bindingSpecifier.positionAfterSkippingLeadingTrivia)
        }
        continue
      }
      if let function = decl.as(FunctionDeclSyntax.self) {
        emit(at: function.funcKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
        emit(at: subscriptDecl.subscriptKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let typealiasDecl = decl.as(TypeAliasDeclSyntax.self) {
        // Exempt per [RULE-EXEMPT-5] (Protocol-sentinel): a
        // `typealias \`Protocol\` = _FooProtocol` is the
        // hoisted-protocol pattern per [API-IMPL-009], where
        // the typealias IS intended to live in the type's
        // namespace (the docs literally show it inside the
        // type body). Forcing extraction yields empty-body +
        // extension-with-one-typealias for zero semantic gain.
        // Helper lives in `Lint.Rule.Structure.Shared.swift`.
        let aliasName = typealiasDecl.name.text
        if structureIsProtocolSentinelName(aliasName) {
          continue
        }
        emit(at: typealiasDecl.typealiasKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let nested = decl.as(StructDeclSyntax.self) {
        if structureMinimalTypeBodyHasExtensionPatternAttribute(nested.attributes) {
          continue
        }
        emit(at: nested.structKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let nested = decl.as(ClassDeclSyntax.self) {
        if structureMinimalTypeBodyHasExtensionPatternAttribute(nested.attributes) {
          continue
        }
        emit(at: nested.classKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let nested = decl.as(EnumDeclSyntax.self) {
        if structureMinimalTypeBodyHasExtensionPatternAttribute(nested.attributes) {
          continue
        }
        emit(at: nested.enumKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let nested = decl.as(ActorDeclSyntax.self) {
        if structureMinimalTypeBodyHasExtensionPatternAttribute(nested.attributes) {
          continue
        }
        emit(at: nested.actorKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
      if let nested = decl.as(ProtocolDeclSyntax.self) {
        emit(at: nested.protocolKeyword.positionAfterSkippingLeadingTrivia)
        continue
      }
    }
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    if structureMinimalTypeBodyHasExtensionPatternAttribute(node.attributes) {
      return .visitChildren
    }
    checkMembers(node.memberBlock)
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    if structureMinimalTypeBodyHasExtensionPatternAttribute(node.attributes) {
      return .visitChildren
    }
    // Exempt per [RULE-EXEMPT-7] (syntax-visitor-subclass): a
    // `final class XVisitor: SyntaxVisitor` (or other SwiftSyntax
    // visitor-family member) has its member shape dictated by the
    // base class's open visit hooks (`override func visit(_:)`,
    // `visitPost`). The overrides are protocol-shaped members per
    // the SwiftSyntax visitor contract — moving them to an
    // extension yields stored-properties + extension-of-overrides
    // for zero semantic gain. Helper lives in
    // `Lint.Rule.Structure.Shared.swift`. See
    // the rule-exemptions skill.
    if structureExtendsSyntaxVisitor(node.inheritanceClause) {
      return .visitChildren
    }
    checkMembers(node.memberBlock)
    return .visitChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    if structureMinimalTypeBodyHasExtensionPatternAttribute(node.attributes) {
      return .visitChildren
    }
    checkMembers(node.memberBlock)
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    if structureMinimalTypeBodyHasExtensionPatternAttribute(node.attributes) {
      return .visitChildren
    }
    checkMembers(node.memberBlock)
    return .visitChildren
  }
}

/// Implements [RULE-EXEMPT-4] (extension-pattern attribute) for the
/// MinimalTypeBody rule. Types marked `@resultBuilder` or `@Suite`
/// have their member shape dictated by an external informal-protocol
/// contract — SE-0289 for `@resultBuilder` (static builder methods)
/// and swift-testing for `@Suite` (nested `@Suite` substructures per
/// the extension-pattern). The attribute IS the spec; forcing
/// extraction yields empty-body + extension-with-only-witnesses for
/// zero semantic gain.
///
/// Pack-local duplicate of `namingHasExtensionPatternAttribute` in
/// `Lint.Rule.Naming.Shared.swift` — the two packs are independently
/// consumable library products, so the contract is copied rather
/// than shared; semantics match. See the rule-exemptions skill.
///
/// Hoisted from a private method on `StructureMinimalTypeBodyVisitor` to a
/// free function (#43) so `Lint.Rule.Structure.MinimalTypeBody.Fix.swift`
/// can share the exact same exemption the detector uses — the fix must
/// never act where the finding does not fire.
internal func structureMinimalTypeBodyHasExtensionPatternAttribute(
  _ attributes: AttributeListSyntax
) -> Swift.Bool {
  for attribute in attributes {
    guard let attr = attribute.as(AttributeSyntax.self) else { continue }
    let name = attr.attributeName.trimmedDescription
    // #28 defect 7.4: accept the qualified spelling
    // (`@Testing.Suite`) too, matching `Shared.swift`'s handling —
    // the bare-name-only comparison previously dropped the
    // [RULE-EXEMPT-4] exemption for it.
    if name == "resultBuilder" || name == "Suite"
      || name.hasSuffix(".resultBuilder") || name.hasSuffix(".Suite")
    {
      return true
    }
  }
  return false
}
