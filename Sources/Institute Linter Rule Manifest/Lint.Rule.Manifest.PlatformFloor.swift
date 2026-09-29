public import Lint
internal import SwiftSyntax

extension Lint.Rule {
  public static let `platform floor` = Lint.Rule(
    id: "platform floor",
    default: .warning,
    controls: [
      .init(
        id: "platform floor five at 27",
        source: "let package = Package(name: \"Fixture\", platforms: [.macOS(.v27), .iOS(.v27), "
          + ".tvOS(.v27), .watchOS(.v27), .visionOS(.v27)])",
        path: "Package.swift",
        expectation: .clean
      ),
      .init(
        id: "platform floor missing visionOS",
        source: "let package = Package(name: \"Fixture\", platforms: [.macOS(.v27), .iOS(.v27), "
          + ".tvOS(.v27), .watchOS(.v27)])",
        path: "Package.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "platform floor lower version",
        source: "let package = Package(name: \"Fixture\", platforms: [.macOS(.v26), .iOS(.v27), "
          + ".tvOS(.v27), .watchOS(.v27), .visionOS(.v27)])",
        path: "Package.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "platform floor undeclared",
        source: "let package = Package(name: \"Fixture\")",
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
      let visitor = ManifestPlatformFloorVisitor(viewMode: .sourceAccurate)
      visitor.walk(source.tree)
      guard let package = visitor.package else {
        return Lint.Rule.Observation(findings: [], coverage: .measured)
      }
      if let reason = visitor.unmeasured {
        return Lint.Rule.Observation(
          findings: [],
          coverage: .unmeasured(.unsupportedSourceShape(reason))
        )
      }
      let declared = visitor.declared
      let reasons: [Swift.String] =
        declared == nil
        ? ["the package must declare `platforms:` with the five Apple platforms at `.v27`."]
        : manifestPlatformFloorPlatforms.compactMap { platform in
          switch declared?[platform] {
          case .none: "`.\(platform)(.v27)` is missing from `platforms:`."
          case .some("v27"): nil
          case .some(let version): "`.\(platform)` must use `.v27`, not `.\(version)`."
          }
        }
      let location = source.converter.location(for: package)
      let findings = reasons.map { reason in
        Diagnostic.Record(
          location: Source.Location(
            fileID: source.file.fileID,
            filePath: source.file.filePath,
            line: location.line,
            column: location.column
          ),
          severity: severity,
          identifier: "platform floor",
          message: "[platform floor] [PACKAGE-PLATFORM-FLOOR]: \(reason)"
        )
      }
      return Lint.Rule.Observation(findings: findings, coverage: .measured)
    }
  )
}

private let manifestPlatformFloorPlatforms: [Swift.String] = [
  "macOS", "iOS", "tvOS", "watchOS", "visionOS",
]

internal final class ManifestPlatformFloorVisitor: SyntaxVisitor {
  var package: AbsolutePosition?
  var declared: [Swift.String: Swift.String]?
  var unmeasured: Swift.String?

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard package == nil,
      node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Package"
    else {
      return .visitChildren
    }
    package = node.positionAfterSkippingLeadingTrivia
    guard let argument = node.arguments.first(where: { $0.label?.text == "platforms" }) else {
      return .skipChildren
    }
    guard let array = argument.expression.as(ArrayExprSyntax.self) else {
      unmeasured = "`platforms:` is not an array literal"
      return .skipChildren
    }
    var platforms: [Swift.String: Swift.String] = [:]
    for element in array.elements {
      guard let call = element.expression.as(FunctionCallExprSyntax.self),
        let name = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
        let version = call.arguments.first?.expression.as(MemberAccessExprSyntax.self)?
          .declName.baseName.text
      else {
        unmeasured = "a `platforms:` element is not `.platform(.version)`"
        return .skipChildren
      }
      platforms[name] = version
    }
    declared = platforms
    return .skipChildren
  }
}
