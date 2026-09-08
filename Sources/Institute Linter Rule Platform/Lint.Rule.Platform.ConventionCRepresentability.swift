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

/// Wave 3 (mechanization-program) — `@convention(c)` function types
/// MUST NOT take `UnsafeMutablePointer<UserType>?` parameters where
/// `UserType` is a Swift-defined struct.
///
/// Citation: `[PLAT-ARCH-005b]` (platform skill — `@convention(c)`
/// representability pre-check).
extension Lint.Rule {
    public static let `convention c representability` = Lint.Rule(
        id: "convention c representability",
        default: .warning,
        controls: [
            .init(
                id: "convention c representability swift struct pointer",
                source: "let callback: @convention(c) "
                    + "(UnsafeMutablePointer<Kernel.Signal.Information>?) -> Void",
                path: "Sources/Platform Core/SwiftStructCallback.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "convention c representability primitive pointer",
                source: "let callback: @convention(c) (UnsafeMutablePointer<Int32>?) -> Void",
                path: "Sources/Platform Core/PrimitiveCallback.swift",
                expectation: .clean
            ),
            .init(
                id: "convention c representability swift convention",
                source: "let callback: (UnsafeMutablePointer<Kernel.Signal.Information>?) -> Void",
                path: "Sources/Platform Core/SwiftCallback.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let visitor = PlatformConventionCRepresentabilityVisitor(
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
internal let platformConventionCRepresentabilityMessage: Swift.String =
    "[convention c representability] [PLAT-ARCH-005b]: `@convention(c)` "
    + "function type takes `UnsafeMutablePointer<UserType>?` for a "
    + "Swift-defined struct — pure Swift structs (including @safe "
    + "wrappers) are NOT C-representable and the compiler rejects "
    + "them in @convention(c) signatures. Use `OpaquePointer?` or "
    + "`UnsafeMutableRawPointer?` in the callback signature; bind the "
    + "typed wrapper at the callback's first line."

internal func platformConventionCRepresentabilityHasConventionC(
    _ attributes: AttributeListSyntax
)
    -> Swift.Bool
{
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        guard attr.attributeName.trimmedDescription == "convention" else { continue }
        if let arguments = attr.arguments,
            case .argumentList(let labeled) = arguments
        {
            if let first = labeled.first,
                let identifier = first.expression.as(DeclReferenceExprSyntax.self),
                identifier.baseName.text == "c"
            {
                return true
            }
        }
    }
    return false
}

/// Returns true when `type` (after stripping optional / IUO /
/// attributed wrappers) is `UnsafeMutablePointer<X>` /
/// `UnsafePointer<X>` where `X` is a Swift-defined struct — i.e. NOT
/// itself an `UnsafeMutablePointer`/`UnsafePointer` type, NOT a type
/// reached through a known C-interop module qualifier (`Darwin.kevent`,
/// `Glibc.stat`, etc. — genuinely C-representable, and the house style
/// for reaching such types in exactly the platform code this rule
/// targets), and NOT one of the stdlib's own C-representable
/// fixed-layout primitives (`[PLAT-ARCH-005b]` exemption, #34).
///
/// Both a bare bare `MyStruct` (`IdentifierTypeSyntax`) and a
/// Swift-namespace-qualified `MyNamespace.MyStruct`
/// (`MemberTypeSyntax` whose root is NOT a C-interop module) count as
/// Swift-defined; only a `MemberTypeSyntax` rooted at a recognized
/// C-interop module, or a bare identifier matching the closed stdlib
/// primitive set, is exempt.
internal func platformConventionCRepresentabilityIsUnsafePointerToUserType(
    _ type: TypeSyntax
)
    -> Swift.Bool
{
    var current = type
    while let optional = current.as(OptionalTypeSyntax.self) {
        current = optional.wrappedType
    }
    while let iuo = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        current = iuo.wrappedType
    }
    while let attributed = current.as(AttributedTypeSyntax.self) {
        current = attributed.baseType
    }
    guard let identifier = current.as(IdentifierTypeSyntax.self) else {
        return false
    }
    guard
        identifier.name.text == "UnsafeMutablePointer"
            || identifier.name.text == "UnsafePointer"
    else { return false }
    guard let genericArgs = identifier.genericArgumentClause,
        let argument = genericArgs.arguments.first,
        let argumentType = argument.argument.as(TypeSyntax.self)
    else { return false }
    if platformConventionCRepresentabilityIsCInteropReference(argumentType) { return false }
    if platformConventionCRepresentabilityIsStdlibPrimitive(argumentType) { return false }
    return true
}

/// True when `type` is a bare identifier naming one of the stdlib's
/// closed set of C-representable fixed-layout primitives: the
/// fixed-width integers, `Int`/`UInt`, `Float`, `Double`, `Bool`, and
/// the raw/opaque pointer types. Being a "Swift-defined struct" is an
/// implementation detail of these types, not an ABI fact — they are
/// the canonical `@convention(c)`-compatible primitives under Swift's
/// C interop rules, and pointers to them MUST NOT be flagged (#34).
///
/// The match is by exact spelling against the closed set, never a
/// prefix or substring test — a type merely named like a primitive
/// (`Int128`, a project-local `Int32Wrapper`) is not itself one of
/// these spellings and remains subject to the rule.
private func platformConventionCRepresentabilityIsStdlibPrimitive(
    _ type: TypeSyntax
)
    -> Swift.Bool
{
    guard let identifier = type.as(IdentifierTypeSyntax.self) else { return false }
    return platformConventionCRepresentabilityStdlibPrimitiveNames.contains(identifier.name.text)
}

private let platformConventionCRepresentabilityStdlibPrimitiveNames: Swift.Set<Swift.String> = [
    "Int8", "Int16", "Int32", "Int64",
    "UInt8", "UInt16", "UInt32", "UInt64",
    "Int", "UInt",
    "Float", "Double",
    "Bool",
    "UnsafeRawPointer", "UnsafeMutableRawPointer", "OpaquePointer",
]

/// True when `type` is a `MemberTypeSyntax` rooted at a recognized
/// C-interop module (`Darwin`, `Glibc`, `Musl`, `Bionic`, `Android`,
/// `WASILibc`, `WinSDK`, `ucrt`, `CRT` — the same module set
/// `canimport conditional` treats as genuine C-library availability).
/// A bare identifier (no qualifier at all) is never a C-interop
/// reference — it's exactly the documented "Swift-defined struct"
/// case this rule exists to catch.
private func platformConventionCRepresentabilityIsCInteropReference(
    _ type: TypeSyntax
)
    -> Swift.Bool
{
    guard let member = type.as(MemberTypeSyntax.self) else { return false }
    var base = member.baseType
    while let nested = base.as(MemberTypeSyntax.self) { base = nested.baseType }
    guard let root = base.as(IdentifierTypeSyntax.self) else { return false }
    return platformPlatformConditionalCLibraryModules.contains(root.name.text)
}

internal final class PlatformConventionCRepresentabilityVisitor: SyntaxVisitor {
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

    override func visit(_ node: AttributedTypeSyntax) -> SyntaxVisitorContinueKind {
        guard platformConventionCRepresentabilityHasConventionC(node.attributes) else {
            return .visitChildren
        }
        guard let function = node.baseType.as(FunctionTypeSyntax.self) else {
            return .visitChildren
        }
        for parameter in function.parameters {
            guard
                platformConventionCRepresentabilityIsUnsafePointerToUserType(
                    parameter.type
                )
            else { continue }
            let location = converter.location(
                for: parameter.type.positionAfterSkippingLeadingTrivia
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
                    identifier: "convention c representability",
                    message: platformConventionCRepresentabilityMessage
                )
            )
        }
        return .visitChildren
    }
}
