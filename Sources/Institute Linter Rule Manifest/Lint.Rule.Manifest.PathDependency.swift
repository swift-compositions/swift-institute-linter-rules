public import Lint
internal import SwiftSyntax

extension Lint.Rule {
  public static let `path dependency` = Lint.Rule(
    id: "path dependency",
    default: .warning,
    controls: [
      .init(
        id: "path dependency local package",
        source: "let package = Package(name: \"Fixture\", "
          + "dependencies: [.package(path: \"../swift-owner\")])",
        path: "Package.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "path dependency named local package",
        source: "let dependency = Package.Dependency.package(name: \"swift-owner\", path: \"../swift-owner\")",
        path: "Package@swift-6.4.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "path dependency url",
        source: "let package = Package(name: \"Fixture\", dependencies: ["
          + ".package(url: \"https://github.com/swift-atoms/swift-owner.git\", branch: \"main\")])",
        path: "Package.swift",
        expectation: .clean
      ),
      .init(
        id: "path dependency target path",
        source: "let target = Target.target(name: \"Fixture\", path: \"Sources/Fixture\")",
        path: "Package.swift",
        expectation: .clean
      ),
      .init(
        id: "path dependency outside manifest",
        source: "let dependency = Package.Dependency.package(path: \"../swift-owner\")",
        path: "Sources/Fixture/Fixture.swift",
        expectation: .clean
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
      let visitor = ManifestPathDependencyVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return Lint.Rule.Observation(findings: visitor.matches, coverage: .measured)
    }
  )
}

@usableFromInline
internal let manifestPathDependencyMessage: Swift.String =
  "[path dependency] [PACKAGE-PATH-DEPENDENCY]: a package dependency must be "
  + "declared by URL, never by `path:`; local checkouts are provided by the "
  + "workspace, not by the manifest."

internal final class ManifestPathDependencyVisitor: SyntaxVisitor {
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

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
      member.declName.baseName.text == "package",
      node.arguments.contains(where: { $0.label?.text == "path" })
    {
      let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
      matches.append(
        Diagnostic.Record(
          location: Source.Location(
            fileID: source.fileID,
            filePath: source.filePath,
            line: location.line,
            column: location.column
          ),
          severity: severity,
          identifier: "path dependency",
          message: manifestPathDependencyMessage
        )
      )
    }
    return .visitChildren
  }
}
