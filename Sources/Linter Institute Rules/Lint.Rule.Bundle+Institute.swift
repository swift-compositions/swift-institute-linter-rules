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

extension Lint.Rule.Bundle {
    public static let institute: [Lint.Rule.Configuration] =
        Lint.Rule.Bundle.universal + [
            .enable(.`architecture import boundary`),
            .enable(.`architecture foundation type`),
            .enable(.`architecture namespace shape`),
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
            .enable(.`phantom suppression`),
            .enable(.`unification typealias`),
            .enable(.`diagnostic message format`),
            .enable(.`foundation import`),
            .enable(.`xctest import`),
            .enable(.`uint8 conforms to byte protocol`),
            .enable(.`byte conforms to arithmetic protocol`),
            .enable(.`binary serializable uint8 witness`),
            .enable(.`binary serializable rawvalue uint8`),
            .enable(.`uint8 ascii extension`),
            .enable(.`uint8 forwarder missing disfavored`),
            .enable(.`stdlib forwarder outside sli`),
            .enable(.`leaf body typealias missing`),
            .enable(.`configuration before content`),
            .enable(.`lifecycle order`),
            .enable(.`unlabeled lifecycle closure`),
            .enable(.`bounded index static capacity`),
            .enable(.`enumerated with subscript`),
            .enable(.`intermediate binding then return`),
            .enable(.`counter loop iteration`),
            .enable(.`string utf8 scanning`),
            .enable(.`sli literal`),  // [IDX-019] (/promote-rule 2026-07-06)
            .enable(.`unknown default`),
            .enable(.`bare string dependency`),
            .enable(.`path dependency`),
            .enable(.`exported import`),
            .enable(.`comment in source`),
            .enable(.`fatal error outside tests`),
            .enable(.`unchecked try outside tests`),
            .enable(.`test target naming`),
            .enable(.`default trait`),
            .enable(.`package policy revision 1`),
            .enable(.`manifest naming grammar`),
            .enable(.`path name grammar`),
            .enable(.`foundation integration leaf target`),
            .enable(.`borrowing self short circuit`),
            .enable(.`noncopyable error`),
            .enable(.`extension noncopyable constraint`),
            .enable(.`nonisolated unsafe without invariant`),
            .enable(.`safe attribute undocumented`),
            .enable(.`pointer advanced by`),
            .enable(.`sendable struct with class member`),
            .enable(.`unchecked sendable revalidation anchor`),
            .enable(.`unsafe assignment granularity`),
            .enable(.`sending return conditional sendable state`),
            .enable(.`c type in public api`),
            .enable(.`convention c representability`),
            .enable(.`dead case per platform`),
            .enable(.`compound platform namespace root`),
            .enable(.`optimize suppression attribute`),  // [ISSUE-008] (/promote-rule 2026-07-06)
            .enable(.`optionset shell pattern`),
            .enable(.`platform layer import`),
            .enable(.`canimport conditional`),
            .enable(.`swift protocol qualification`),
            .enable(.`system subdomain`),
            .enable(.`typealiased namespace bridge`),
            .enable(.`hoisted protocol alias`),
            .enable(.`minimal type body`),
            .enable(.`raw value access`),
            .enable(.`single type per file`),
            .enable(.`file name nested path`),
            .enable(.`extension file naming`),
            .enable(.`throwing wrapper init`),
            .enable(.`type transform placement`),
            .enable(.`wrapper backing exposed`),
            .enable(.`protocol sentinel under generic front door`),
            .enable(.`test file suffix`),
            .enable(.`test function naming`),
            .enable(.`performance suite serialized`),
            .enable(.`test display name string`),
            .enable(.`closure typed throws annotation`),
            .enable(.`do throws for typed catch`),
            .enable(.`do throws for typed catch with throw`),
            .enable(.`existential throws`),
            .enable(.`generic throws missing never`),
            .enable(.`hoisted error in public throws`),
            .enable(.`fully qualified error in typed throws`),
            .enable(.`lifecycle typealias review`),
            .enable(.`callback result over throws thunk`),
            .enable(.`result wrapper for rethrows shim`),
            .enable(.`typed throws cannot use self error`),
            .enable(.`untyped throws`),
            .enable(.`try optional`),
            .enable(.`unchecked call site`),
            .enable(.`zero or one literal`),
            .enable(.`count minus one`),
            .enable(.`bitpattern rawvalue chain`),
            .enable(.`chained rawvalue access`),
            .enable(.`tagged extension public init`),
            .enable(.`tagged unchecked with typed alternative`),
        ]
}
