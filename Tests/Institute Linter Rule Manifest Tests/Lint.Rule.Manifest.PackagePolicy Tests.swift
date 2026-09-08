import Lint
import Linter_Rules_Test_Support
import Testing

@testable import Institute_Linter_Rule_Manifest

extension Lint.Rule {
  @Suite
  struct `package policy revision 1 Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`package policy revision 1 Tests` {
  static let clean = """
    // swift-tools-version: 6.4

    import PackageDescription

    let package = Package(
        name: "fixture",
        platforms: [.macOS(.v27), .iOS(.v27)],
        targets: [.target(name: "Fixture")],
        swiftLanguageModes: [.v6]
    )

    for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
        target.swiftSettings = (target.swiftSettings ?? []) + [
            .strictMemorySafety(),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableExperimentalFeature("Lifetimes"),
            .enableUpcomingFeature("InferIsolatedConformances"),
        ]
    }
    """

  static func observation(
    _ source: Swift.String,
    file: Swift.String = "Package.swift"
  ) -> Lint.Rule.Observation {
    let parsed = Lint.Source.parsed(from: source, file: file)
    return Lint.Rule.`package policy revision 1`.observe(parsed, .error)
  }
}

extension Lint.Rule.`package policy revision 1 Tests`.Unit {
  @Test
  func `complete executable revision is clean`() {
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(
      Lint.Rule.`package policy revision 1 Tests`.clean
    )
    #expect(observation.coverage == .measured)
    #expect(observation.findings.isEmpty)
  }

  @Test
  func `each missing target setting is an exact finding`() {
    let dirty = Lint.Rule.`package policy revision 1 Tests`.clean.replacing(
      ".enableUpcomingFeature(\"InferIsolatedConformances\"),",
      with: ""
    )
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(dirty)
    #expect(observation.coverage == .measured)
    #expect(observation.findings.count == 1)
    #expect(observation.findings[0].message.contains("InferIsolatedConformances"))
  }

  @Test
  func `concrete language and platform drift are findings`() {
    let dirty = Lint.Rule.`package policy revision 1 Tests`.clean
      .replacing(".macOS(.v27)", with: ".macOS(.v26)")
      .replacing("swiftLanguageModes: [.v6]", with: "swiftLanguageModes: [.v5]")
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(dirty)
    #expect(observation.coverage == .measured)
    #expect(observation.findings.count == 2)
  }
}

extension Lint.Rule.`package policy revision 1 Tests`.`Edge Case` {
  @Test
  func `computed language mode is unmeasured`() {
    let source = Lint.Rule.`package policy revision 1 Tests`.clean.replacing(
      "swiftLanguageModes: [.v6]",
      with: "swiftLanguageModes: modes"
    )
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(source)
    #expect(observation.findings.isEmpty)
    #expect(
      observation.coverage
        == .unmeasured(.unsupportedSourceShape("computed or noncanonical swiftLanguageModes"))
    )
  }

  @Test
  func `unrecognized target-setting application is unmeasured`() {
    let marker =
      "for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type)"
    let source = Lint.Rule.`package policy revision 1 Tests`.clean.replacing(
      marker,
      with: "for target in ordinaryTargets(package)"
    )
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(source)
    guard case .unmeasured = observation.coverage else {
      Issue.record("computed target scope was accepted as measured")
      return
    }
  }

  @Test
  func `L1 macro target is rejected`() {
    let source = """
      // swift-tools-version: 6.4
      import PackageDescription
      let package = Package(
          name: "macro-fixture",
          targets: [.macro(name: "Fixture Macro")],
          swiftLanguageModes: [.v6]
      )
      """
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(
      source,
      file: "/workspace/swift-molecules/macro-fixture/Package.swift"
    )
    #expect(observation.coverage == .measured)
    #expect(observation.findings.count == 1)
    #expect(observation.findings[0].message.contains("must not declare a macro"))
  }
}

extension Lint.Rule.`package policy revision 1 Tests`.Integration {
  @Test
  func `dirty to clean control and typed repair refusal`() {
    let dirty = Lint.Rule.`package policy revision 1 Tests`.clean.replacing(
      "// swift-tools-version: 6.4",
      with: "// swift-tools-version: 6.3"
    )
    #expect(
      Lint.Rule.`package policy revision 1 Tests`.observation(dirty).findings.count == 1
    )
    #expect(
      Lint.Rule.`package policy revision 1 Tests`.observation(
        Lint.Rule.`package policy revision 1 Tests`.clean
      ).findings.isEmpty
    )

    let parsed = Lint.Source.parsed(from: dirty, file: "Package.swift")
    #expect(
      Lint.Rule.`package policy revision 1`.repair(parsed)
        == .refused(.repairUnavailable)
    )
  }

  @Test
  func `ordinary source is not applicable`() {
    let observation = Lint.Rule.`package policy revision 1 Tests`.observation(
      "struct Package {}",
      file: "Sources/Package.swift"
    )
    #expect(!observation.applicability.isApplicable)
    #expect(observation.coverage == .measured)
  }
}
