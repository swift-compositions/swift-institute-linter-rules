import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Manifest

extension Lint.Rule {
  @Suite
  struct `platform floor Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`platform floor Tests` {
  static func observation(
    _ source: Swift.String,
    file: Swift.String = "Package.swift"
  ) -> Lint.Rule.Observation {
    Lint.Rule.`platform floor`.observe(Lint.Source.parsed(from: source, file: file), .warning)
  }
}

extension Lint.Rule.`platform floor Tests`.Unit {
  @Test
  func `five platforms at 27 are clean`() {
    let observation = Lint.Rule.`platform floor Tests`.observation(
      """
      let package = Package(
          name: "Fixture",
          platforms: [
              .macOS(.v27),
              .iOS(.v27),
              .tvOS(.v27),
              .watchOS(.v27),
              .visionOS(.v27),
          ]
      )
      """
    )
    #expect(observation.coverage == .measured)
    #expect(observation.findings.isEmpty)
  }

  @Test
  func `each missing or lower platform is flagged`() {
    let observation = Lint.Rule.`platform floor Tests`.observation(
      """
      let package = Package(
          name: "Fixture",
          platforms: [.macOS(.v26), .iOS(.v27)]
      )
      """
    )
    #expect(observation.findings.count == 4)
    #expect(observation.findings[0].message.hasPrefix("[platform floor] [PACKAGE-PLATFORM-FLOOR]:"))
    #expect(observation.findings[0].message.contains("`.macOS` must use `.v27`, not `.v26`"))
  }
}

extension Lint.Rule.`platform floor Tests`.`Edge Case` {
  @Test
  func `a package without platforms is flagged once`() {
    let observation = Lint.Rule.`platform floor Tests`.observation(
      "let package = Package(name: \"Fixture\")"
    )
    #expect(observation.findings.count == 1)
  }

  @Test
  func `computed platforms are unmeasured`() {
    let observation = Lint.Rule.`platform floor Tests`.observation(
      "let platforms: [SupportedPlatform] = []\nlet package = Package(name: \"Fixture\", platforms: platforms)"
    )
    #expect(observation.coverage != .measured)
    #expect(observation.findings.isEmpty)
  }

  @Test
  func `non-manifest files are inapplicable`() {
    let observation = Lint.Rule.`platform floor Tests`.observation(
      "let package = Package(name: \"Fixture\")",
      file: "Sources/Fixture/Fixture.swift"
    )
    #expect(observation.applicability == .inapplicable)
  }
}

extension Lint.Rule.`platform floor Tests`.Integration {
  @Test
  func `a versioned manifest is checked`() {
    let observation = Lint.Rule.`platform floor Tests`.observation(
      "let package = Package(name: \"Fixture\", platforms: [.macOS(.v27), .iOS(.v27), .tvOS(.v27), .watchOS(.v27)])",
      file: "Package@swift-6.4.swift"
    )
    #expect(observation.findings.count == 1)
    #expect(observation.findings[0].message.contains("visionOS"))
  }
}
