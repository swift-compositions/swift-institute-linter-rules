import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Architecture

extension Lint.Rule {
  @Suite
  struct `exported import Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`exported import Tests` {
  static func findings(
    _ source: Swift::String,
    file: Swift::String = "Sources/Fixture/exports.swift"
  ) -> [Diagnostic.Record] {
    Lint.Rule.`exported import`
      .observe(Lint.Source.parsed(from: source, file: file), .warning)
      .findings
  }
}

extension Lint.Rule.`exported import Tests`.Unit {
  @Test
  func `every exported import is flagged`() {
    let findings = Lint.Rule.`exported import Tests`.findings(
      """
      @_exported public import Owner
      @_exported import Other
      public import Plain
      """
    )
    #expect(findings.count == 2)
    #expect(findings[0].message.hasPrefix("[exported import] [SOURCE-EXPORTED-IMPORT]:"))
  }

  @Test
  func `plain imports are clean`() {
    let findings = Lint.Rule.`exported import Tests`.findings(
      "public import Owner\ninternal import Other"
    )
    #expect(findings.isEmpty)
  }
}

extension Lint.Rule.`exported import Tests`.`Edge Case` {
  @Test
  func `tests are out of scope`() {
    let findings = Lint.Rule.`exported import Tests`.findings(
      "@_exported import Owner",
      file: "Tests/Fixture Tests/exports.swift"
    )
    #expect(findings.isEmpty)
  }

  @Test
  func `a scoped exported import is flagged`() {
    let findings = Lint.Rule.`exported import Tests`.findings(
      "@_exported import struct Owner.Value"
    )
    #expect(findings.count == 1)
  }
}

extension Lint.Rule.`exported import Tests`.Integration {
  @Test
  func `an exported import behind a condition is flagged`() {
    let findings = Lint.Rule.`exported import Tests`.findings(
      """
      #if canImport(Owner)
      @_exported public import Owner
      #endif
      """,
      file: "/workspace/swift-fixture/Sources/Fixture/exports.swift"
    )
    #expect(findings.count == 1)
  }
}
