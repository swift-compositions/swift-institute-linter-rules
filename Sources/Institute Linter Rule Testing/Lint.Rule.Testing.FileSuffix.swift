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

/// Test suite files are named `<Subject> Tests.swift` — a space before
/// `Tests` (for example, `Array.Dynamic Tests.swift`, never
/// `Array.DynamicTests.swift`).
///
/// Citation: `[TEST-009]`.
///
/// The rule's surface is a source file under a test target whose
/// declarations contain at least one `@Suite`-attributed type or at
/// least one `@Test`-attributed function. The rule fires when the
/// file's basename does not end in ` Tests` (exactly one space,
/// capital T) before `.swift`.
///
/// Excluded from the surface by predicate, not exemption: test-target
/// files with no `@Suite` or `@Test` declarations — helpers, fixtures,
/// and support files carry no required suffix. (Known accepted false
/// negative: a suite file whose attributes are hidden behind
/// conditional compilation inactive on the scanning platform is not
/// detected.) Non-test targets are out of scope entirely.
///
/// The diagnostic is located at the file's first `@Suite` type or
/// `@Test` function. The canonical fix is a rename: insert the space
/// before `Tests`, or, for a basename ending in neither form, append
/// ` Tests` to the subject name. No source edit.
extension Lint.Rule {
    public static let `test file suffix` = Lint.Rule(
        id: "test file suffix",
        default: .warning,
        controls: [
            .init(
                id: "test file suffix joined suffix",
                source: "@Suite struct ValueTests {}",
                path: "Tests/Testing Tests/ValueTests.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "test file suffix spaced suffix",
                source: "@Suite struct `Value Tests` {}",
                path: "Tests/Testing Tests/Value Tests.swift",
                expectation: .clean
            ),
            .init(
                id: "test file suffix production scope",
                source: "@Suite struct ValueTests {}",
                path: "Sources/Testing Support/ValueTests.swift",
                expectation: .clean
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            let filePath = source.file.filePath
            let components = filePath.split(separator: "/", omittingEmptySubsequences: true)
            guard components.contains("Tests") else { return [] }
            // Exempt any path carrying a hidden path component (dot-prefixed
            // directory, e.g. `.build/`) — deliberately also matches a `..`
            // relative-path segment, since that's dot-prefixed too and is
            // never itself a real target directory name.
            guard !components.contains(where: { $0.hasPrefix(".") }) else { return [] }
            guard
                let filename = components.last,
                filename.hasSuffix(".swift")
            else {
                return []
            }
            let basename = Swift.String(filename.dropLast(".swift".count))
            // #24 defect 8: `hasSuffix(" Tests")` alone also accepts
            // `Foo  Tests.swift` (two spaces), since "  Tests" itself ends
            // in " Tests". Require exactly one space immediately before
            // `Tests`.
            let hasExactlyOneSpaceBeforeTests =
                basename.hasSuffix(" Tests") && !basename.hasSuffix("  Tests")
            guard !hasExactlyOneSpaceBeforeTests else { return [] }
            let finder = TestingFileSuffixDeclarationFinder(viewMode: .sourceAccurate)
            finder.walk(source.tree)
            guard let position = finder.first else { return [] }
            let location = source.converter.location(for: position)
            return [
                Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.file.fileID,
                        filePath: filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "test file suffix",
                    message: testingFileSuffixMessage(basename: basename)
                )
            ]
        }
    )
}

/// Builds the `[TEST-009]` diagnostic message for a nonconforming
/// basename, naming the canonical rename.
@usableFromInline
internal func testingFileSuffixMessage(basename: Swift.String) -> Swift.String {
    "[test file suffix] [TEST-009]: test file '\(basename).swift' must end in "
        + "' Tests.swift'; rename to '\(testingFileSuffixRename(basename: basename)).swift'"
}

/// Computes the canonical conforming basename for a nonconforming one:
/// insert the space before a joined `Tests` suffix, or append ` Tests`
/// to a subject name ending in neither form. Trailing-whitespace
/// variance around the suffix is normalized by the rename.
@usableFromInline
internal func testingFileSuffixRename(basename: Swift.String) -> Swift.String {
    func trimmed(_ string: Swift.Substring) -> Swift.Substring {
        var slice = string
        while slice.last == " " { slice = slice.dropLast() }
        return slice
    }
    let base = trimmed(basename[...])
    guard base.hasSuffix("Tests") else { return "\(base) Tests" }
    let subject = trimmed(base.dropLast("Tests".count))
    guard !subject.isEmpty else { return "\(base) Tests" }
    return "\(subject) Tests"
}

/// Records the position of the file's first `@Suite`-attributed type
/// declaration or `@Test`-attributed function declaration.
internal final class TestingFileSuffixDeclarationFinder: SyntaxVisitor {
    var first: AbsolutePosition?

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(attributes: node.attributes, name: "Suite", of: Syntax(node))
        return first == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(attributes: node.attributes, name: "Suite", of: Syntax(node))
        return first == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(attributes: node.attributes, name: "Suite", of: Syntax(node))
        return first == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(attributes: node.attributes, name: "Suite", of: Syntax(node))
        return first == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(attributes: node.attributes, name: "Test", of: Syntax(node))
        return .skipChildren
    }

    private func record(
        attributes: AttributeListSyntax,
        name: Swift.String,
        of node: Syntax
    ) {
        guard first == nil else { return }
        for attribute in attributes {
            guard case .attribute(let a) = attribute else { continue }
            let attributeName = a.attributeName.trimmedDescription
            if attributeName == name || attributeName.hasSuffix(".\(name)") {
                first = node.positionAfterSkippingLeadingTrivia
                return
            }
        }
    }
}
