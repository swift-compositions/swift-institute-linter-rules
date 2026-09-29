public import Lint
internal import SwiftSyntax

extension Lint.Rule {
  public static let `canonical settings tail` = Lint.Rule(
    id: "canonical settings tail",
    default: .warning,
    controls: [
      .init(
        id: "canonical settings tail canonical",
        source: "let package = Package(name: \"Fixture\")\n\n" + manifestCanonicalSettingsTail,
        path: "Package.swift",
        expectation: .clean
      ),
      .init(
        id: "canonical settings tail missing",
        source: "let package = Package(name: \"Fixture\")\n",
        path: "Package.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "canonical settings tail drifted",
        source: "let package = Package(name: \"Fixture\")\n\n"
          + "for target in package.targets {\n"
          + "    target.swiftSettings = [.strictMemorySafety()]\n"
          + "}\n",
        path: "Package.swift",
        expectation: .findings(1)
      ),
    ],
    observe: { source, severity in
      guard manifestIsPackageManifest(source.file.filePath) else {
        return Lint.Rule.Observation(
          findings: [],
          coverage: .measured,
          applicability: .inapplicable
        )
      }
      let text = source.tree.description
      let tail = text.range(of: manifestCanonicalSettingsTailHead).map { Swift.String(text[$0.lowerBound...]) }
      guard manifestCanonicalSettingsTailNormalized(tail) != manifestCanonicalSettingsTailNormalized(manifestCanonicalSettingsTail)
      else {
        return Lint.Rule.Observation(findings: [], coverage: .measured)
      }
      let line =
        text.range(of: manifestCanonicalSettingsTailHead)
        .map { text[..<$0.lowerBound].count(where: { $0 == "\n" }) + 1 } ?? 1
      let reason =
        tail == nil
        ? "the manifest must end with the canonical settings tail"
        : "the settings tail differs from the canonical shape"
      return Lint.Rule.Observation(
        findings: [
          Diagnostic.Record(
            location: Source.Location(
              fileID: source.file.fileID,
              filePath: source.file.filePath,
              line: line,
              column: 1
            ),
            severity: severity,
            identifier: "canonical settings tail",
            message: "[canonical settings tail] [PACKAGE-SETTINGS-TAIL]: \(reason); "
              + "regenerate it with swift-linter's Scripts/settings-tail.py."
          )
        ],
        coverage: .measured
      )
    }
  )
}

@usableFromInline
internal let manifestCanonicalSettingsTailHead: Swift.String = "for target in package.targets"

@usableFromInline
internal let manifestCanonicalSettingsTail: Swift.String = """
  for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
      target.swiftSettings = (target.swiftSettings ?? []) + [
          .strictMemorySafety(),
          .enableUpcomingFeature("ExistentialAny"),
          .enableUpcomingFeature("InternalImportsByDefault"),
          .enableUpcomingFeature("MemberImportVisibility"),
          .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
          .enableUpcomingFeature("InferIsolatedConformances"),
          .enableExperimentalFeature("Lifetimes"),
          .treatAllWarnings(as: .error),
      ]
  }

  """

internal func manifestCanonicalSettingsTailNormalized(_ text: Swift.String?) -> Swift.String? {
  text.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
