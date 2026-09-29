import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Structure

extension Lint.Rule {
  @Suite
  struct `comment in source Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`comment in source Tests` {
  static func findings(
    _ source: Swift::String,
    file: Swift::String = "Sources/Fixture/Fixture.swift"
  ) -> [Diagnostic.Record] {
    Lint.Rule.`comment in source`
      .observe(Lint.Source.parsed(from: source, file: file), .warning)
      .findings
  }
}

extension Lint.Rule.`comment in source Tests`.Unit {
  @Test
  func `line documentation and block comments are each flagged`() {
    let findings = Lint.Rule.`comment in source Tests`.findings(
      """
      // Note
      /// A value.
      /* block */
      struct Value {
          let count = 1 // trailing
          /** documentation block */
          let name = ""
      }
      """
    )
    #expect(findings.count == 5)
    #expect(findings[0].message.hasPrefix("[comment in source] [SOURCE-NO-COMMENTS]:"))
  }

  @Test
  func `code without comments is clean`() {
    let findings = Lint.Rule.`comment in source Tests`.findings(
      "struct Value {\n    let count = 1\n}"
    )
    #expect(findings.isEmpty)
  }
}

extension Lint.Rule.`comment in source Tests`.`Edge Case` {
  @Test
  func `swift-linter directives are admitted`() {
    let findings = Lint.Rule.`comment in source Tests`.findings(
      """
      // swift-linter:disable:next comment in source
      let value = 1 // swift-linter:disable:this some rule
      """
    )
    #expect(findings.isEmpty)
  }

  @Test
  func `comment markers inside string literals are not comments`() {
    let findings = Lint.Rule.`comment in source Tests`.findings(
      """
      let a = "// not a comment"
      let b = \"\"\"
          /// still text
          \"\"\"
      """
    )
    #expect(findings.isEmpty)
  }

  @Test
  func `tests are out of scope`() {
    let findings = Lint.Rule.`comment in source Tests`.findings(
      "// note\nstruct Value {}",
      file: "Tests/Fixture Tests/Fixture Tests.swift"
    )
    #expect(findings.isEmpty)
  }
}

extension Lint.Rule.`comment in source Tests`.Integration {
  @Test
  func `a license header is flagged line by line`() {
    let findings = Lint.Rule.`comment in source Tests`.findings(
      """
      // Copyright (c) 2026 Example
      // Licensed under Apache License v2.0

      struct Value {}
      """,
      file: "/workspace/swift-fixture/Sources/Fixture/Value.swift"
    )
    #expect(findings.count == 2)
  }
}

extension Lint.Rule.`comment in source Tests`.Integration {
  static func repaired(_ source: Swift::String) -> Swift::String? {
    let proposal = Lint.Rule.`comment in source`.repair(
      Lint.Source.parsed(from: source, file: "Sources/Fixture/Fixture.swift")
    )
    guard case .edits(let edits) = proposal, case .rewrite(_, let contents) = edits.first else {
      return nil
    }
    return contents
  }

  @Test
  func `repair removes whole-line, documentation and trailing comments`() {
    let repaired = Self.repaired(
      """
      // Header
      import Lint

      /// A value.
      struct Value {
          /// The count.
          let count = 1 // trailing
          /* block */
          let name = ""
      }
      """
    )
    #expect(
      repaired == """
        import Lint

        struct Value {
            let count = 1
            let name = ""
        }
        """
    )
  }

  @Test
  func `repair keeps swift-linter directives`() {
    let source = "// swift-linter:disable:next some rule\nlet value = 1"
    #expect(Lint.Rule.`comment in source`.repair(Lint.Source.parsed(from: source, file: "Sources/Fixture/Fixture.swift")) == .unchanged)
  }

  @Test
  func `repaired source is clean`() {
    let repaired = Self.repaired("/// Doc\nfunc f() {} // note\n")
    #expect(repaired.map { Lint.Rule.`comment in source Tests`.findings($0).isEmpty } == true)
  }
}
