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

public import Institute_Linter_Rule_Architecture
public import Institute_Linter_Rule_Byte
public import Institute_Linter_Rule_Cardinal
public import Institute_Linter_Rule_Closure
public import Institute_Linter_Rule_Conformance
public import Institute_Linter_Rule_Foundation
public import Institute_Linter_Rule_Framework
public import Institute_Linter_Rule_Idiom
public import Institute_Linter_Rule_Manifest
public import Institute_Linter_Rule_Memory
public import Institute_Linter_Rule_Naming
public import Institute_Linter_Rule_Platform
public import Institute_Linter_Rule_RawValue
public import Institute_Linter_Rule_Structure
public import Institute_Linter_Rule_Testing
public import Institute_Linter_Rule_Throws
public import Institute_Linter_Rule_Try
public import Institute_Linter_Rule_Unchecked
public import Lint
public import Linter_Rules

/// Institute-tier rule bundle.
///
/// Equals the universal-tier bundle plus institute-tier rules currently
/// living in `swift-institute-linter-rules`. A consumer that pulls this
/// bundle by name receives the full union without enumerating
/// individual rules:
///
/// ```swift
/// let configuration = Lint.Configuration {
///     Lint.Rule.Bundle.institute
/// }
/// ```
///
/// As mixed packs are split out of `swift-linter-rules` into this
/// package, this bundle's content grows; the universal bundle's
/// content sharpens. Consumers continue to reference
/// `Lint.Rule.Bundle.institute` and pick up the migration
/// automatically.
///
/// ## Severity-tier policy
///
/// This repository's graduation discipline, made explicit (anchors the
/// bundle's existing "advisory at introduction; error only after the
/// standing graduation gate" comments to one standing rule):
///
/// 1. **A rule is born `.warning`.** `default: .error` is not available
///    at introduction, without exception.
/// 2. **Promotion to `.error` requires all three:**
///    (a) **Structural predicate** — the rule decides on AST shape.
///    Textual matching of source spellings, name-suffix heuristics, and
///    path heuristics each disqualify.
///    (b) **Both-direction fixtures for every exemption and carve-out
///    the rule carries.** An untested exemption is an unbounded silent
///    hole and is disqualifying on its own.
///    (c) **Fleet evidence that is non-zero and adjudicated.** A fleet
///    zero is *never* evidence for promotion: zero is equally
///    consistent with a clean fleet and a blind predicate. Only a
///    non-zero run whose every finding was adjudicated — fixed,
///    suppressed with a reason, or ruled a false positive and the
///    predicate corrected — supports promotion.
/// 3. **Demotion needs only (a) failing.** A demonstrated
///    non-structural predicate at `.error` is demoted immediately;
///    demotion strictly reduces enforcement and so cannot break a
///    converging root.
/// 4. **Scope.** This governs a rule's `default:` severity in this
///    repository. A consumer's configured override is out of scope,
///    and nothing here promotes anything.
extension Lint.Rule.Bundle {
    public static let institute: [Lint.Rule.Configuration] =
        Lint.Rule.Bundle.universal + [
            // Architecture pack (TX-A2, swift-compositions/swift-linter#44) —
            // AST-local architecture predicates supplied for the derived-model
            // programme; advisory at introduction per this bundle's severity-tier
            // policy, and fleet enforcement binds at TX-A4 (.github#85 amendment
            // 5), never here.
            .enable(.`architecture import boundary`),
            .enable(.`architecture foundation type`),
            .enable(.`architecture namespace shape`),
            // Naming pack
            .enable(.`bool public parameter`),
            .enable(.`ad hoc box class`),
            .enable(.`compound identifier`),
            .enable(.`compound suite name`),
            .enable(.`compound type name`),
            .enable(.`variable named impl`),
            .enable(.`int public parameter`),
            .enable(.`namespace adoption typealias`),
            .enable(.`property named flags`),
            .enable(.`redundant prefix`),
            .enable(.`single type namespace`),
            .enable(.`tag suffix`),
            .enable(.`nested tag`),
            // [API-NAME-010b] — validated 2026-07-07 against the ADT tower
            // (tree-keyed 1, slab 5, buffer-slab 2 = 8 true-positive findings on
            // phantom `<E: ~Copyable>` Index discriminators; the dominant fleet
            // convention binds such phantoms `~Copyable & ~Escapable`, 99 sites).
            // Receipt: Research/promote-phantom-suppression-tower-validation-2026-07-07.md.
            .enable(.`phantom suppression`),
            .enable(.`unification typealias`),
            // [API-NAME-009] — mirrors validate-diagnostic-format.py
            // (swift-institute/.github#358 F9, predicate parity). Advisory at
            // introduction; error only after the standing graduation gate.
            .enable(.`diagnostic message format`),
            // Foundation pack
            .enable(.`foundation import`),
            // Framework pack
            .enable(.`xctest import`),
            // `suite categories` is intentionally disabled: tests use the
            // `<Domain>.Test` subdomain without mandatory Unit/Edge Case/
            // Integration scaffolding.
            // Byte pack (Wave 1 of Post-W2 swift-linter arc, 2026-05-19)
            // — encodes the W2 UInt8/Byte discrimination rubric per
            // the L2/L3 byte-typing gap plan note § Wave 2.
            .enable(.`uint8 conforms to byte protocol`),
            .enable(.`byte conforms to arithmetic protocol`),
            .enable(.`binary serializable uint8 witness`),
            .enable(.`binary serializable rawvalue uint8`),
            .enable(.`uint8 ascii extension`),
            .enable(.`uint8 forwarder missing disfavored`),
            .enable(.`stdlib forwarder outside sli`),
            // Conformance pack
            .enable(.`leaf body typealias missing`),
            // Closure pack (Wave 3 2026-05-15)
            .enable(.`configuration before content`),
            .enable(.`lifecycle order`),
            .enable(.`unlabeled lifecycle closure`),
            // `parameter position` is intentionally disabled: a semantically
            // labeled closure can read better before the value it operates over
            // (for example `check(of:over:)`).
            // Idiom pack (Wave 3 2026-05-15)
            .enable(.`bounded index static capacity`),
            .enable(.`enumerated with subscript`),
            .enable(.`intermediate binding then return`),
            .enable(.`counter loop iteration`),
            .enable(.`string utf8 scanning`),
            .enable(.`sli literal`),  // [IDX-019] (/promote-rule 2026-07-06)
            // Implemented per swift-institute-linter-rules#4; advisory at
            // introduction, error only after the graduation gate.
            .enable(.`unknown default`),
            // Manifest dependency spellings are measured structurally;
            // computed or unhandled shapes fail closed as unmeasured.
            .enable(.`bare string dependency`),
            .enable(.`package policy revision 1`),
            // [#65, principal directive 2026-08-09] — manifest naming
            // grammar: package kebab slug, spaced product/target names,
            // declared-path correspondence. Advisory at introduction; error
            // only after the standing graduation gate. Known-open findings
            // (institute-application's pre-split InstituteArchitecture*
            // names) are enumerated on #65 as the respacing transaction's
            // work list, not forced to zero.
            .enable(.`manifest naming grammar`),
            // [#65, principal directive 2026-08-09; Nest.Name directory
            // ruling 2026-08-06] — path naming grammar: directory segments
            // and declared-type file basename segments. The ruled Workspace
            // validator was audited and found unimplemented; the owner
            // decision (linter Naming family) is recorded in the rule doc.
            // Advisory at introduction; error only after the standing
            // graduation gate.
            .enable(.`path name grammar`),
            // [swift-structured-queries#2 ruling, 2026-07-30] —
            // implemented per swift-institute-linter-rules#31. Advisory at
            // introduction; error only after the standing graduation gate.
            .enable(.`foundation integration leaf target`),
            // Memory pack (Wave 3 2026-05-15)
            .enable(.`borrowing self short circuit`),
            .enable(.`noncopyable error`),
            .enable(.`extension noncopyable constraint`),
            .enable(.`nonisolated unsafe without invariant`),
            .enable(.`safe attribute undocumented`),
            .enable(.`pointer advanced by`),
            .enable(.`sendable struct with class member`),
            .enable(.`unchecked sendable revalidation anchor`),
            .enable(.`unsafe assignment granularity`),
            // [swift-property#7 adjudication] — implemented per
            // swift-institute-linter-rules#29. Advisory at introduction;
            // error only after the standing graduation gate.
            .enable(.`sending return conditional sendable state`),
            // Platform pack (Wave 3 2026-05-15)
            .enable(.`c type in public api`),
            .enable(.`convention c representability`),
            .enable(.`dead case per platform`),
            .enable(.`compound platform namespace root`),
            .enable(.`optimize suppression attribute`),  // [ISSUE-008] (/promote-rule 2026-07-06)
            .enable(.`optionset shell pattern`),
            // [PLAT-ARCH-008] — mirrors validate-layer-deps.py
            // check_plat_arch_008 (swift-institute/.github#358 F9, predicate
            // parity). Advisory at introduction; error only after the standing
            // graduation gate.
            .enable(.`platform layer import`),
            .enable(.`canimport conditional`),
            .enable(.`swift protocol qualification`),
            .enable(.`system subdomain`),
            .enable(.`typealiased namespace bridge`),
            // Structure pack (Wave 3 2026-05-15)
            .enable(.`hoisted protocol alias`),
            // License-header policy is intentionally undecided; neither
            // presence nor absence is enforced by the institute bundle.
            .enable(.`minimal type body`),
            .enable(.`raw value access`),
            .enable(.`single type per file`),
            // [API-IMPL-006] — adjudicated swift-institute-linter-rules#6
            // (ruling D1, 2026-07-30); implemented per
            // swift-institute-linter-rules#8. Advisory at introduction; error
            // only after the standing graduation gate.
            .enable(.`file name nested path`),
            // [API-IMPL-007] — adjudicated swift-institute-linter-rules#6
            // (ruling D2, 2026-07-30); implemented per
            // swift-institute-linter-rules#9. Advisory at introduction; error
            // only after the standing graduation gate.
            .enable(.`extension file naming`),
            .enable(.`throwing wrapper init`),
            .enable(.`type transform placement`),
            .enable(.`wrapper backing exposed`),
            // [swift-institute/.github#122 ruling, disposition c, W7] —
            // implemented per swift-institute-linter-rules#30. Advisory at
            // introduction; error only after the standing graduation gate.
            .enable(.`protocol sentinel under generic front door`),
            // Testing pack (Wave 3 2026-05-15)
            // `benchmark timed required` ([BENCH-003]) deferred 2026-05-18:
            // depends on swift-testing's `.timed()` trait which isn't
            // production-ready; benchmarks are moving to separate
            // /Benchmarks/ packages per the `benchmark` skill, so the rule's
            // target audience (in-tree Performance @Suites) is going away.
            // Re-enable when (a) swift-testing's `.timed()` ships stable OR
            // (b) we readopt in-tree Performance @Suites with a different
            // measurement primitive. The rule definition stays in the
            // Institute_Linter_Rule_Testing module for re-enable convenience.
            // .enable(.`benchmark timed required`),
            // [TEST-009] — implemented per swift-institute-linter-rules#10;
            // advisory at introduction, error only after the graduation gate.
            .enable(.`test file suffix`),
            .enable(.`test function naming`),
            .enable(.`performance suite serialized`),
            // [SWIFT-TEST-006] — implemented per swift-institute-linter-rules#37;
            // advisory at introduction, error only after the graduation gate.
            .enable(.`test display name string`),
            // Throws pack (Wave 3 2026-05-15)
            .enable(.`closure typed throws annotation`),
            .enable(.`do throws for typed catch`),
            .enable(.`do throws for typed catch with throw`),
            .enable(.`existential throws`),
            .enable(.`generic throws missing never`),
            .enable(.`hoisted error in public throws`),
            .enable(.`fully qualified error in typed throws`),
            // Swift 6.4 no longer reproduces the optimizer failure which led
            // to the `__` hoisting workaround, so the legacy phantom rule is
            // retained for older toolchains but disabled in this bundle.
            .enable(.`lifecycle typealias review`),
            .enable(.`callback result over throws thunk`),
            .enable(.`result wrapper for rethrows shim`),
            .enable(.`typed throws cannot use self error`),
            .enable(.`untyped throws`),
            // Try pack (Wave 3 2026-05-15)
            .enable(.`try optional`),
            // Unchecked pack (Wave 3 2026-05-15)
            .enable(.`unchecked call site`),
            // A5 move (2026-07-07, principal ruling) — brand-consumer rule packs
            // relocated from swift-primitives-linter-rules so they enforce at L2/L3
            // too (brands are defined at L1 but consumed everywhere). Precedent:
            // [PRIM-FOUND-001] made the same primitives→institute move mid-pilot.
            // Cardinal pack (Wave 3 2026-05-15)
            .enable(.`zero or one literal`),
            .enable(.`count minus one`),
            // RawValue pack
            .enable(.`bitpattern rawvalue chain`),
            .enable(.`chained rawvalue access`),
            .enable(.`tagged extension public init`),
            // [CONV-015] — promoted 2026-07-07 (principal ruling, option a)
            // from swift-tagged' nested Lint/ PoC
            // (Lint.Rule.TaggedDomainAudit); map/retag/@Test exemptions
            // preserved. NOTE: the validation receipt this promotion cites is
            // not committed to Research/ in this repository (see issue #16) —
            // treat the citation as unresolved until the receipt is either
            // committed here or the citation is corrected upstream.
            .enable(.`tagged unchecked with typed alternative`),
        ]
}
