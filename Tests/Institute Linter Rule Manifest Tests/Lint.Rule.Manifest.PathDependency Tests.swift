import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Manifest

extension Lint.Rule {
  @Suite
  struct `path dependency Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`path dependency Tests` {
  static func observation(
    _ source: Swift.String,
    file: Swift.String = "Package.swift"
  ) -> Lint.Rule.Observation {
    Lint.Rule.`path dependency`.observe(Lint.Source.parsed(from: source, file: file), .warning)
  }
}

extension Lint.Rule.`path dependency Tests`.Unit {
  @Test
  func `path dependency in the package dependencies is flagged`() {
    let observation = Lint.Rule.`path dependency Tests`.observation(
      """
      let package = Package(
          name: "Fixture",
          dependencies: [
              .package(url: "https://github.com/swift-atoms/swift-owner.git", branch: "main"),
              .package(path: "../swift-other"),
          ]
      )
      """
    )
    #expect(observation.coverage == .measured)
    #expect(observation.findings.count == 1)
    #expect(observation.findings[0].message.hasPrefix("[path dependency] [PACKAGE-PATH-DEPENDENCY]:"))
  }

  @Test
  func `url dependencies are clean`() {
    let observation = Lint.Rule.`path dependency Tests`.observation(
      """
      let package = Package(
          name: "Fixture",
          dependencies: [
              .package(url: "https://github.com/swift-atoms/swift-owner.git", branch: "main"),
          ]
      )
      """
    )
    #expect(observation.findings.isEmpty)
  }
}

extension Lint.Rule.`path dependency Tests`.`Edge Case` {
  @Test
  func `a target path is not a package dependency`() {
    let observation = Lint.Rule.`path dependency Tests`.observation(
      "let target = Target.target(name: \"Fixture\", path: \"Sources/Fixture\")"
    )
    #expect(observation.findings.isEmpty)
  }

  @Test
  func `non-manifest files are inapplicable`() {
    let observation = Lint.Rule.`path dependency Tests`.observation(
      "let dependency = Package.Dependency.package(path: \"../swift-owner\")",
      file: "Sources/Fixture/Fixture.swift"
    )
    #expect(observation.findings.isEmpty)
    #expect(observation.applicability == .inapplicable)
  }
}

extension Lint.Rule.`path dependency Tests`.Integration {
  @Test
  func `named path dependency in a versioned manifest is flagged`() {
    let observation = Lint.Rule.`path dependency Tests`.observation(
      "let dependency = Package.Dependency.package(name: \"swift-owner\", path: \"../swift-owner\")",
      file: "Package@swift-6.4.swift"
    )
    #expect(observation.findings.count == 1)
  }
}
