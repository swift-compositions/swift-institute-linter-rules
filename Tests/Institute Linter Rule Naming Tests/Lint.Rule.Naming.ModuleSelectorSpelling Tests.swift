import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Naming

extension Lint.Rule {
  @Suite
  struct `module selector spelling Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`module selector spelling Tests` {
  static func findings(
    _ source: Swift.String,
    file: Swift.String = "Sources/Fixture/Fixture.swift"
  ) -> [Diagnostic.Record] {
    Lint.Rule.`module selector spelling`
      .observe(Lint.Source.parsed(from: source, file: file), .warning)
      .findings
  }
}

extension Lint.Rule.`module selector spelling Tests`.Unit {
  @Test
  func `standard library member qualification is flagged in types and expressions`() {
    let findings = Lint.Rule.`module selector spelling Tests`.findings(
      """
      func f(_ value: Swift.Int) -> Swift.String {
          Swift.print(value)
          return ""
      }
      """
    )
    #expect(findings.count == 3)
    #expect(findings[0].message.hasPrefix("[module selector spelling] [SOURCE-MODULE-SELECTOR]:"))
  }

  @Test
  func `module selectors are clean`() {
    let findings = Lint.Rule.`module selector spelling Tests`.findings(
      "func f(_ value: Swift::Int) -> Swift::String { \"\" }"
    )
    #expect(findings.isEmpty)
  }
}

extension Lint.Rule.`module selector spelling Tests`.`Edge Case` {
  @Test
  func `a namespace type sharing its module's name is not flagged`() {
    let findings = Lint.Rule.`module selector spelling Tests`.findings(
      "import Lint\nlet rule: Lint.Rule? = nil\nlet other = Lint.Rule.self"
    )
    #expect(findings.isEmpty)
  }

  @Test
  func `nested qualification is flagged once`() {
    let findings = Lint.Rule.`module selector spelling Tests`.findings(
      "let index: Swift.String.Index? = nil"
    )
    #expect(findings.count == 1)
  }
}

extension Lint.Rule.`module selector spelling Tests`.Integration {
  @Test
  func `imported target modules count as modules`() {
    let findings = Lint.Rule.`module selector spelling Tests`.findings(
      """
      internal import Institute_Fixture_Core
      let value = Institute_Fixture_Core.Value()
      let type: Institute_Fixture_Core.Value.Type = Institute_Fixture_Core.Value.self
      """
    )
    #expect(findings.count == 3)
  }
}

extension Lint.Rule.`module selector spelling Tests`.Integration {
  static func repaired(_ source: Swift.String) -> Swift.String? {
    let proposal = Lint.Rule.`module selector spelling`.repair(
      Lint.Source.parsed(from: source, file: "Sources/Fixture/Fixture.swift")
    )
    guard case .edits(let edits) = proposal, case .rewrite(_, let contents) = edits.first else {
      return nil
    }
    return contents
  }

  @Test
  func `repair spells module qualification with a selector`() {
    let repaired = Self.repaired(
      """
      internal import Institute_Fixture_Core
      func f(_ value: Swift.Int, index: Swift.String.Index?) -> Swift.String {
          Swift.print(Institute_Fixture_Core.Value.self)
          return ""
      }
      """
    )
    #expect(
      repaired == """
        internal import Institute_Fixture_Core
        func f(_ value: Swift::Int, index: Swift::String.Index?) -> Swift::String {
            Swift::print(Institute_Fixture_Core::Value.self)
            return ""
        }
        """
    )
    #expect(repaired.map { Lint.Rule.`module selector spelling Tests`.findings($0).isEmpty } == true)
  }

  @Test
  func `repair leaves selector spelling unchanged`() {
    let proposal = Lint.Rule.`module selector spelling`.repair(
      Lint.Source.parsed(from: "let value: Swift::Int = 0", file: "Sources/Fixture/Fixture.swift")
    )
    #expect(proposal == .unchanged)
  }
}
