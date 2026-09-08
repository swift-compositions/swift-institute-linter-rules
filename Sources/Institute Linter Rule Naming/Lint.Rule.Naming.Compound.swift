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

/// Wave-1 — compound identifiers (verb-noun camelCase methods/properties).
///
/// Citation: [API-NAME-002].
///
/// Methods and properties MUST NOT use compound names — use nested
/// accessors instead (`instance.open.write { }` not `instance.openWrite { }`).
/// Compound type names are governed by [API-NAME-001] and require
/// type-info to disambiguate spec-mirroring exceptions; this rule
/// targets only the lower-risk method / property compound case.
extension Lint.Rule {
  public static let `compound identifier` = Lint.Rule(
    id: "compound identifier",
    default: .warning,
    controls: [
      .init(
        id: "compound identifier public compound",
        source: "public func openWrite() {}",
        path: "Sources/Naming Core/Compound.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "compound identifier single token",
        source: "public func open() {}",
        path: "Sources/Naming Core/SingleToken.swift",
        expectation: .clean
      ),
      .init(
        id: "compound identifier boolean prefix",
        source: "public var isEmpty: Bool { false }",
        path: "Sources/Naming Core/BooleanPrefix.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      // Scan-scope gate (BEFORE the walk): a SwiftPM manifest is build
      // configuration, not API surface. See `namingIsPackageManifest`.
      guard !namingIsPackageManifest(source.file.filePath) else { return [] }
      let visitor = NamingCompoundVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

private let namingCompoundMessage: Swift.String =
  "[compound identifier] [API-NAME-002]: method or property has a compound "
  + "camelCase name (e.g., `walkFiles` instead of `walk.files()`). "
  + "**Default disposition**: refactor to nested accessors — "
  + "`instance.open.write { }` not `instance.openWrite { }`; "
  + "`dir.walk.files()` not `dir.walkFiles()`. "
  + "**Already exempt** (rule does not fire): boolean prefixes "
  + "(`is`/`has`/`should`/`will`/`did`/`can`/`must`); declarations below "
  + "`package` visibility, because they are not consumer-observable API; swift-testing "
  + "scaffolding — declarations carrying `@Test`/`@Suite` and members of a "
  + "`@Suite` type, per #53 (a compound `@Test` name is still reported, by "
  + "`test function naming`, whose fix is the backticked descriptive form); "
  + "terminology in targets declared by the source profile as preserving vocabulary "
  + "imposed by an external specification authority; "
  + "documented "
  + "stdlib-vocabulary names (`rawValue`, `flatMap`, `swapAt`, `storeBytes`, "
  + "`withUnsafeBufferPointer`, etc. — see "
  + "`namingCompoundSwiftNativeIdiomCitations` in this rule's source for "
  + "the full citation set); the 8 `@resultBuilder` method names per "
  + "SE-0289/SE-0348. "
  + "**A finding does not by itself mean the name must change.** This rule "
  + "checks the SHAPE of the name; it cannot see whether a namespace to "
  + "group into exists, nor why the name was chosen. Measured over the #53 "
  + "pilot, most surviving findings correctly resolve to leaving the code "
  + "alone. Two shapes are known-legitimate and are NOT recognizable from "
  + "syntax, so the rule still fires on them by design: (a) a two-word "
  + "property with no sibling in its type sharing a leading word — there is "
  + "nothing to group, and the single-member decision tree says not to "
  + "manufacture a namespace (the rule cannot check this: the "
  + "one-extension-per-member file convention scatters a type's members "
  + "across files, and a same-file sibling test would exempt nearly "
  + "everything); (b) vocabulary held deliberately in lockstep with a cited "
  + "external reference implementation outside a profile-declared externally standardized "
  + "target, where renaming breaks traceability to the source. For either, leave "
  + "the code and — where the site warrants "
  + "a durable record — suppress that one site with "
  + "`// swift-linter:disable:next compound identifier` plus a `// REASON:` "
  + "naming the shape or citing the reference. "
  + "**Accept-as-warning** disposition (rule fires legitimately, leave the "
  + "warning): when the name mirrors a stdlib type's API at a consumer-"
  + "facing typed-input bridge (e.g., a typed-Cardinal-input overload of "
  + "`OutputSpan.removeLast` mirrors `Array.removeLast(_:Int)`), OR a "
  + "protocol this extension conforms to requires this exact name but "
  + "isn't yet in the witness allowlist "
  + "(`namingCompoundProtocolWitnessMethodCitations` in this rule's "
  + "source — entries are proposed in lint drains with a "
  + "`Protocol.requirement` citation and ratified per #16 Option C "
  + "Entry III.d). The warning IS the intended "
  + "signal — review each canary, confirm the justification still holds, "
  + "leave the warning. Don't silently disable; don't fix-source against "
  + "the rule's intent. If you've confirmed a name is broadly applicable "
  + "stdlib-mirror vocabulary, propose adding it to "
  + "`namingCompoundSwiftNativeIdiomCitations` with its Swift citation."

private let namingCompoundBooleanPrefixes: [Swift.String] = [
  "is", "has", "should", "will", "did", "can", "must",
]

/// Identifiers exempt from the compound-name rule because they align with
/// Swift-native vocabulary (the stdlib chose the compound spelling for
/// the same concept). Each key cites its canonical Swift-native seed —
/// adding an entry without a citation makes the exemption indefensible
/// at review time. The dict shape replaces the prior unsourced
/// `Set<String>` form.
///
/// The Either / Optional / Result `flatMap` precedent: Swift.Optional
/// chose `flatMap` (not `bind`) as the canonical monadic-bind name;
/// institute types that implement the same operation align with that
/// choice rather than introducing a parallel vocabulary.
private let namingCompoundSwiftNativeIdiomCitations: [Swift.String: Swift.String] = [
  "rawValue": "Swift.RawRepresentable.rawValue",
  "customMirror": "Swift.CustomReflectable.customMirror",
  "description": "Swift.CustomStringConvertible.description",
  "debugDescription": "Swift.CustomDebugStringConvertible.debugDescription",
  "hashValue": "Swift.Hashable.hashValue (deprecated but still applies)",
  "bitPattern": "Swift.UInt32.bitPattern / Swift.UInt64.bitPattern",
  "startIndex": "Swift.Collection.startIndex",
  "endIndex": "Swift.Collection.endIndex",
  "flatMap": "Swift.Optional.flatMap — canonical monadic-bind name",
  "compactMap": "Swift.Sequence.compactMap(_:) / Swift.Optional.compactMap(_:)",
  "forEach": "Swift.Sequence.forEach(_:)",
  "allSatisfy": "Swift.Sequence.allSatisfy(_:)",
  // Stdlib with-helper functions: scoped-resource patterns the stdlib
  // ships as compound names (`withX` accumulates the scoped-action
  // operand into the name). Following the stdlib precedent rather
  // than reinventing parallel vocabulary.
  "withUnsafeBufferPointer":
    "Swift.Array.withUnsafeBufferPointer / Swift.Span.withUnsafeBufferPointer",
  "withUnsafeMutableBufferPointer":
    "Swift.Array.withUnsafeMutableBufferPointer / Swift.MutableSpan.withUnsafeMutableBufferPointer",
  "withContiguousStorageIfAvailable": "Swift.Sequence.withContiguousStorageIfAvailable",
  "withUnsafeMutablePointerToElements": "Swift.ManagedBuffer.withUnsafeMutablePointerToElements",
  "withUnsafeMutablePointerToHeader": "Swift.ManagedBuffer.withUnsafeMutablePointerToHeader",
  "withUnsafeMutablePointers": "Swift.ManagedBuffer.withUnsafeMutablePointers",
  "withCheckedContinuation": "Swift._Concurrency.withCheckedContinuation",
  "withTaskCancellationHandler": "Swift._Concurrency.withTaskCancellationHandler",
  "withUnsafeContinuation": "Swift._Concurrency.withUnsafeContinuation",
  "withUnsafePointer": "Swift.withUnsafePointer(to:_:)",
  "withUnsafeMutablePointer": "Swift.withUnsafeMutablePointer(to:_:)",
  "withUnsafeBytes": "Swift.withUnsafeBytes(of:_:)",
  "withUnsafeMutableBytes": "Swift.withUnsafeMutableBytes(of:_:)",
  "withUnsafeTemporaryAllocation": "Swift.withUnsafeTemporaryAllocation(byteCount:alignment:_:)",
  // Swift.Result error transforms — compound names align with the
  // stdlib Result type's documented API.
  "mapError": "Swift.Result.mapError(_:)",
  "flatMapError": "Swift.Result.flatMapError(_:)",
  // Dictionary key/value transforms — institute counterparts to
  // Swift.Dictionary.mapValues / compactMapValues.
  "mapKeys": "Swift.Dictionary.mapValues(_:) precedent (institute counterpart)",
  "compactMapKeys": "Swift.Dictionary.compactMapValues(_:) precedent (institute counterpart)",
  // swift-algorithms ecosystem precedent for deduplication.
  "uniqued": "swift-algorithms.uniqued() — Sequence/Collection deduplication",
  // SE-0517 span accessors: stdlib added `var span: Span<Element>` and
  // `var mutableSpan: MutableSpan<Element>` as canonical computed
  // properties for non-copyable Span access on Array / ContiguousArray /
  // friends. Institute types implementing the same protocol contract
  // mirror the stdlib's spelling rather than introducing a parallel
  // vocabulary.
  "span": "SE-0517 Span / MutableSpan — Swift.Array.span (canonical span getter)",
  "mutableSpan":
    "SE-0517 Span / MutableSpan — Swift.Array.mutableSpan (canonical mutable-span getter)",
  // Scoped-access counterparts to the `span` / `mutableSpan` computed
  // properties above — the stdlib `withX` scoped-borrow idiom applied to
  // the same SE-0517 non-copyable Span access. Ratified per the
  // swift-array#9 adjudication (comment 5134794606,
  // 2026-07-30), Escalation item 1; six-name #32 batch.
  "withSpan": "SE-0517 Span scoped-access counterpart to the allowlisted `span` getter",
  "withMutableSpan":
    "SE-0517 MutableSpan scoped-access counterpart to the allowlisted `mutableSpan` getter",
  // Swift.Array bulk-mutation vocabulary the front-door institute
  // container types mirror to preserve their `Swift.Array`-shadowing
  // source-compatibility contract ([DS-028]). Ratified per the
  // swift-array#9 adjudication (comment 5134794606,
  // 2026-07-30), Escalation item 1; six-name #32 batch.
  "removeAll": "Swift.Array.removeAll(keepingCapacity:)",
  "reserveCapacity": "Swift.Array.reserveCapacity(_:)",
  // Stdlib `withX` scoped-borrow family, applied to a single-element
  // scoped access. Declared across 8 packages in swift-molecules.
  // Ratified per the swift-array#9 adjudication (comment
  // 5134794606, 2026-07-30), Escalation item 1; six-name #32 batch.
  "withElement":
    "stdlib withX scoped-borrow family — 8 declaring packages across swift-molecules",
  // L1 container-family vocabulary: the identical member exists on
  // `SlotMap` (swift-slot-map), `Queue`
  // (swift-queue), and `Queue.DoubleEnded`
  // (swift-deque) in addition to `Array` — 4 declaring
  // packages. Ratified per the swift-array#9 adjudication
  // (comment 5134794606, 2026-07-30), Escalation item 1; six-name
  // #32 batch.
  "freeCapacity": "L1 container-family vocabulary — 4 declaring packages across swift-molecules",
  // SE-0253 callable values of user-defined nominal types: the compiler
  // recognises a method literally named `callAsFunction` and synthesises
  // `instance(args)` call-site syntax against it. The compound name is
  // dictated by the language feature, not the author.
  "callAsFunction": "SE-0253 — compiler-recognised callable-as-function informal protocol",
  // Stdlib typed-index / pointer overload names: institute overloads
  // on stdlib types (`UnsafeMutablePointer`, `UnsafeMutableRawPointer`,
  // `OutputSpan`) that accept institute Ordinal/Cardinal indices in
  // place of `Int` follow the stdlib spelling — the operation IS the
  // stdlib operation with a typed index.
  "swapAt": "Swift.MutableCollection.swapAt(_:_:)",
  "storeBytes": "Swift.UnsafeMutableRawPointer.storeBytes(of:toByteOffset:as:)",
  "moveInitialize": "Swift.UnsafeMutablePointer.moveInitialize(from:count:)",
  // Stdlib integer division-with-remainder protocol method.
  "quotientAndRemainder": "Swift.BinaryInteger.quotientAndRemainder(dividingBy:)",
  // Swift.Sequence underestimated-count protocol-required property.
  // Surfaces on institute Sequence-conforming types whose iterator
  // count is known at compile time (e.g., `Cyclic.Group.Static`).
  "underestimatedCount": "Swift.Sequence.underestimatedCount",
]

/// Method names that are protocol-required witnesses on a stdlib or
/// institute protocol — the witness allowlist the rule's accept-as-warning
/// arm refers to. Formalized by the #16 Option C ledger, Entry III.d
/// (DECISION 2026-07-23):
///
/// - **Who adds entries**: entries are proposed in lint drains and
///   ratified by the principal (or a session holding delegated
///   adjudication authority); the ratifying adjudication is cited in the
///   entry's comment when the entry is institute-protocol-sourced.
/// - **Citation**: each entry names the specific `Protocol.requirement`
///   whose contract dictates the name. Adding an entry without a
///   citation is indefensible at review time ([RULE-EXEMPT-2]).
/// - **Effect**: allowlisted witnesses stop firing entirely inside their
///   gate (below); outside it they still fire.
///
/// Gate (`conformanceGated`): when `true`, the exemption requires the
/// enclosing context to introduce a conformance (`Naming.conformances`
/// non-empty — [RULE-EXEMPT-3]); outside that context the compound name
/// still fires. When `false`, the entry is name-only: the institute's
/// one-extension-per-member file convention (`Type+method.swift`) places
/// the witness in a bare extension whose conformance is declared in a
/// SIBLING file, which no same-file AST walk can see — the same
/// structural limitation that made `Naming.Build.methods` name-only
/// (see the [RULE-EXEMPT-4] note in this file). Name-only entries MUST
/// be protocol vocabulary distinctive enough that non-witness reuse is
/// implausible.
private let namingCompoundProtocolWitnessMethodCitations:
  [Swift.String: (citation: Swift.String, conformanceGated: Swift.Bool)] = [
    "encodeAtomicRepresentation": (
      "Swift.AtomicRepresentable.encodeAtomicRepresentation(_:)", true
    ),
    "decodeAtomicRepresentation": (
      "Swift.AtomicRepresentable.decodeAtomicRepresentation(_:)", true
    ),
    "makeIterator": ("Swift.Sequence.makeIterator()", true),
    // Identity.OAuth.Provider witnesses (swift-identities-types,
    // `Identity.OAuth.swift` — protocol requirements verified at source).
    // Ratified per #16 Option C Entry III.d (0205e7f seeded the 7 sites).
    // The property witnesses sit in the conformance-declaring extension
    // (`Identity.OAuth.GitHub+Identity.OAuth.Provider.swift`) and are
    // conformance-gated; the method witnesses live in per-method extension
    // files (`Identity.OAuth.GitHub+exchangeCode.swift` etc.) whose
    // conformance is declared in the sibling witness file, so they are
    // name-only per the gate rationale above.
    "displayName": ("Identity.OAuth.Provider.displayName", true),
    "requiresTokenStorage": ("Identity.OAuth.Provider.requiresTokenStorage", true),
    "supportsRefresh": ("Identity.OAuth.Provider.supportsRefresh", true),
    "authorizationURL": ("Identity.OAuth.Provider.authorizationURL(state:redirectURI:)", false),
    "exchangeCode": ("Identity.OAuth.Provider.exchangeCode(_:redirectURI:)", false),
    "getUserInfo": ("Identity.OAuth.Provider.getUserInfo(accessToken:)", false),
    "refreshToken": ("Identity.OAuth.Provider.refreshToken(_:)", false),
    // Institute Sequence.Iterator.`Protocol` sole protocol requirement.
    // Span-based primitive (`mutating func nextSpan(maximumCount:) -> Span<Element>`)
    // is the institute counterpart to Swift.IteratorProtocol's `next()`;
    // see `swift-molecules/swift-sequence/Sources/Sequence Core/Sequence.Iterator.Protocol.swift`.
    "nextSpan":
      (
        "Sequence.Iterator.`Protocol`.nextSpan(maximumCount:) — institute span-based iterator primitive aligned with Swift.IteratorProtocol vocabulary",
        true
      ),
    // Swift.Sequence/RangeReplaceableCollection vocabulary aligned, plus
    // institute Sequence.`Clearable` requirement (`mutating func removeAll()`).
    "removeAll":
      (
        "Swift.RangeReplaceableCollection.removeAll() / Swift.Sequence.removeAll(where:) / Sequence.`Clearable`.removeAll()",
        true
      ),
    // Institute Collection.Remove.Last requirement (`static func removeLast(_:)`),
    // preserving drop-in vocabulary alignment with Swift.Array.removeLast() and
    // Swift.RangeReplaceableCollection.removeLast(). Institute syntax is additive
    // on top: `.remove.last()` is the fluent View accessor; consumers may also
    // expose `removeLast()` instance form for stdlib-compatibility.
    "removeLast":
      (
        "Swift.RangeReplaceableCollection.removeLast() / Swift.Array.removeLast() / Collection.Remove.Last.removeLast(_:) — drop-in stdlib replacement vocabulary",
        true
      ),
  ]

internal final class NamingCompoundVisitor: SyntaxVisitor {
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

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let visibility = Lint.Visibility.effective(of: Syntax(node))
    guard visibility == .public || visibility == .package else {
      return .visitChildren
    }
    // Skip nested function declarations inside function / closure /
    // accessor bodies. The rule's intent ([API-NAME-002]) is
    // public/API surface; local helpers are implementation detail
    // and not part of the named-export surface. Symmetric with
    // the local let/var exemption in `visit(_ node: VariableDeclSyntax)`
    // below. Common in test bodies (`@Test func ... { func readTwice(...) }`)
    // where the helper is bound to the test function's scope.
    if isInsideFunctionLikeContext(Syntax(node)) {
      return .visitChildren
    }
    // Backtick-escape exemption: see `Naming.isBackticked` for the
    // full rationale. Backticks signal the author opted out of
    // standard identifier conventions (narrative, non-identifier-
    // char content, or keyword escape) — the compound-identifier
    // rule targets CamelCase API surface and does not apply.
    if Naming.isBackticked(node.name) {
      return .visitChildren
    }
    // Test-scaffolding exemption (#53). A compound `@Test` function name is
    // retargeted to `test function naming`, which prescribes the correct
    // fix; a fixture in a `@Suite` type is not API surface at all. See
    // `Naming.isTestScaffolding` for why this is an attribute gate and not
    // a `Tests/` path gate.
    if Naming.isTestScaffolding(Syntax(node), attributes: node.attributes) {
      return .visitChildren
    }
    let name = node.name.text
    if name == "visitPost",
      node.modifiers.contains(where: { $0.name.tokenKind == .keyword(.override) })
    {
      return .visitChildren
    }
    guard isCompoundIdentifier(name) else {
      return .visitChildren
    }
    // Exempt per [RULE-EXEMPT-4] (@resultBuilder): the canonical
    // Result Builder method names — `buildExpression`, `buildBlock`,
    // `buildPartialBlock`, `buildOptional`, `buildEither`,
    // `buildArray`, `buildLimitedAvailability`, `buildFinalResult`
    // — are dictated by the `@resultBuilder` informal-protocol
    // contract per SE-0289 / SE-0348. The exemption is NAME-ONLY:
    // we do NOT additionally require the enclosing type to carry
    // `@resultBuilder`. The earlier formulation gated on
    // `Naming.isInsideExtensionPattern` (a walk-up looking for
    // `@resultBuilder` on the enclosing type decl), but that walk
    // cannot cross file boundaries: when a builder's methods are
    // declared in an `extension` whose primary type decl with the
    // attribute lives in a different file, the walker stops at the
    // extension and the exemption never fires. Surfaced 2026-05-15
    // by the byte-extraction arc against
    // `swift-parser/Sources/Parser Core/Parser.Builder.swift`
    // (the extension lives in one file; the `@resultBuilder` decl in
    // another). False-negative risk of name-only relaxation is
    // negligible — the 8 builder method names are unique
    // SE-0289 / SE-0348 spec vocabulary and aren't reused for
    // non-builder semantics in practice.
    if Naming.Build.methods.contains(name) {
      return .visitChildren
    }
    // Exempt per [RULE-EXEMPT-2] (protocol-witness-citation-dict):
    // protocol-required witness method names declared inside an
    // extension whose inheritance clause names the corresponding
    // protocol. `encodeAtomicRepresentation` outside an
    // `AtomicRepresentable` conformance still fires. The dict is
    // the citation surface — each entry pairs a witness name with
    // its specific protocol. Composes with [RULE-EXEMPT-3]
    // (conformance-context) via `namingIsInsideConformingContext`'s
    // lookup-form companion `Naming.conformances`.
    if let entry = namingCompoundProtocolWitnessMethodCitations[name] {
      if !entry.conformanceGated {
        // Name-only witness entry (#16 Entry III.d): the conformance is
        // declared in a sibling file per the one-extension-per-member
        // convention; no same-file walk can gate it.
        return .visitChildren
      }
      let conformances = Naming.conformances(Syntax(node))
      if !conformances.isEmpty {
        return .visitChildren
      }
    }
    emit(at: node.name.positionAfterSkippingLeadingTrivia)
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    let visibility = Lint.Visibility.effective(of: Syntax(node))
    guard visibility == .public || visibility == .package else {
      return .visitChildren
    }
    // Skip local declarations inside function / closure / accessor
    // bodies. The rule's intent ([API-NAME-002]) is public/API
    // surface; local lets and vars are implementation detail and
    // not part of the named-export surface.
    if isInsideFunctionLikeContext(Syntax(node)) {
      return .visitChildren
    }
    // Test-scaffolding exemption (#53) — fixture properties declared in a
    // `@Suite` type or in a bare extension of one. See
    // `Naming.isTestScaffolding`.
    if Naming.isTestScaffolding(Syntax(node), attributes: node.attributes) {
      return .visitChildren
    }
    for binding in node.bindings {
      guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
        continue
      }
      // Backtick-escape exemption (see `Naming.isBackticked`).
      if Naming.isBackticked(pattern.identifier) {
        continue
      }
      let name = pattern.identifier.text
      guard isCompoundIdentifier(name) else {
        continue
      }
      // Exempt per [RULE-EXEMPT-2] (protocol-witness-citation-dict) —
      // property witnesses (`displayName`, `requiresTokenStorage`, …)
      // are dictated by the cited protocol requirement exactly as
      // method witnesses are. Same gate as the function path; #16
      // Option C Entry III.d extended the dict's coverage to the
      // variable path.
      if let entry = namingCompoundProtocolWitnessMethodCitations[name] {
        if !entry.conformanceGated {
          continue
        }
        if !Naming.conformances(Syntax(node)).isEmpty {
          continue
        }
      }
      emit(at: pattern.identifier.positionAfterSkippingLeadingTrivia)
    }
    return .visitChildren
  }

  /// Returns true if a function-like ancestor (function body, init body,
  /// accessor body, closure body, deinit body, or subscript body) is
  /// encountered before a type / extension declaration when walking
  /// up the parent chain. Used to identify declarations that are
  /// local-scope rather than member-of-type.
  private func isInsideFunctionLikeContext(_ node: Syntax) -> Bool {
    var current: Syntax? = node.parent
    while let candidate = current {
      if candidate.is(FunctionDeclSyntax.self)
        || candidate.is(InitializerDeclSyntax.self)
        || candidate.is(AccessorDeclSyntax.self)
        || namingIsShorthandGetterAccessorBlock(candidate)
        || candidate.is(ClosureExprSyntax.self)
        || candidate.is(DeinitializerDeclSyntax.self)
        || candidate.is(SubscriptDeclSyntax.self)
      {
        return true
      }
      if candidate.is(ExtensionDeclSyntax.self)
        || candidate.is(StructDeclSyntax.self)
        || candidate.is(ClassDeclSyntax.self)
        || candidate.is(EnumDeclSyntax.self)
        || candidate.is(ActorDeclSyntax.self)
        || candidate.is(ProtocolDeclSyntax.self)
      {
        return false
      }
      current = candidate.parent
    }
    return false
  }

  private func isCompoundIdentifier(_ name: Swift.String) -> Bool {
    guard namingCompoundSwiftNativeIdiomCitations[name] == nil else {
      return false
    }
    for prefix in namingCompoundBooleanPrefixes {
      if name.hasPrefix(prefix), name.count > prefix.count {
        let nextIndex = name.index(name.startIndex, offsetBy: prefix.count)
        if name[nextIndex].isUppercase {
          return false
        }
      }
    }
    var sawLowercase = false
    var sawUppercaseAfterLowercase = false
    for (offset, character) in name.enumerated() {
      if offset == 0 {
        guard character.isLowercase else {
          return false
        }
        sawLowercase = true
        continue
      }
      if character.isUppercase, sawLowercase {
        sawUppercaseAfterLowercase = true
        break
      }
      if character.isLowercase || character.isNumber || character == "_" {
        continue
      }
      return false
    }
    return sawUppercaseAfterLowercase
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
        identifier: "compound identifier",
        message: namingCompoundMessage
      )
    )
  }
}
