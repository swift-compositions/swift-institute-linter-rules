public import Lint
internal import SwiftSyntax

extension Lint.Rule {
  public static let `upward layer edge` = Lint.Rule(
    id: "upward layer edge",
    default: .warning,
    controls: [
      .init(
        id: "upward layer edge atoms on molecules",
        source: "let package = Package(name: \"swift-owner\", dependencies: ["
          + ".package(url: \"https://github.com/swift-molecules/swift-buffer.git\", branch: \"main\")])",
        path: "/workspace/swift-atoms/swift-owner/Package.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "upward layer edge molecules on atoms",
        source: "let package = Package(name: \"swift-owner\", dependencies: ["
          + ".package(url: \"https://github.com/swift-atoms/swift-byte.git\", branch: \"main\")])",
        path: "/workspace/swift-molecules/swift-owner/Package.swift",
        expectation: .clean
      ),
      .init(
        id: "upward layer edge standards on compositions",
        source: "let package = Package(name: \"swift-owner\", dependencies: ["
          + ".package(url: \"https://github.com/swift-compositions/swift-json.git\", branch: \"main\")])",
        path: "/workspace/swift-standards/swift-iso/swift-owner/Package.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "upward layer edge compositions on all",
        source: "let package = Package(name: \"swift-owner\", dependencies: ["
          + ".package(url: \"https://github.com/swift-ietf/swift-rfc-3986.git\", branch: \"main\"), "
          + ".package(url: \"https://github.com/swift-compositions/swift-json.git\", branch: \"main\")])",
        path: "/workspace/swift-compositions/swift-owner/Package.swift",
        expectation: .clean
      ),
    ],
    observe: { source, severity in
      guard manifestIsPackageManifest(source.file.filePath),
        let layer = manifestLayer(ofPath: source.file.filePath)
      else {
        return Lint.Rule.Observation(
          findings: [],
          coverage: .measured,
          applicability: .inapplicable
        )
      }
      let visitor = ManifestUpwardLayerEdgeVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter,
        layer: layer
      )
      visitor.walk(source.tree)
      return Lint.Rule.Observation(findings: visitor.matches, coverage: .measured)
    }
  )
}

private let manifestLayerNames: [Swift.Int: Swift.String] = [
  1: "atoms", 2: "molecules", 3: "standards", 4: "compositions",
]

private let manifestOrganizationLayers: [Swift.String: Swift.Int] = [
  "swift-atoms": 1,
  "swift-molecules": 2,
  "swift-standards": 3,
  "swift-arm-ltd": 3,
  "swift-bipm": 3,
  "swift-ecma": 3,
  "swift-iec": 3,
  "swift-ieee": 3,
  "swift-ietf": 3,
  "swift-incits": 3,
  "swift-intel": 3,
  "swift-iso": 3,
  "swift-linux-foundation": 3,
  "swift-microsoft": 3,
  "swift-riscv": 3,
  "swift-w3c": 3,
  "swift-whatwg": 3,
  "swift-compositions": 4,
]

internal func manifestLayer(ofPath path: Swift.String) -> Swift.Int? {
  let components = path.split(separator: "/").map(Swift.String.init)
  return components.dropLast().compactMap { component in
    switch component {
    case "swift-atoms": 1
    case "swift-molecules": 2
    case "swift-standards": 3
    case "swift-compositions": 4
    default: nil
    }
  }.first
}

internal func manifestLayer(ofURL url: Swift.String) -> Swift.Int? {
  let prefix = "https://github.com/"
  guard url.hasPrefix(prefix) else { return nil }
  let organization = url.dropFirst(prefix.count).split(separator: "/").first.map(Swift.String.init)
  return organization.flatMap { manifestOrganizationLayers[$0] }
}

internal final class ManifestUpwardLayerEdgeVisitor: SyntaxVisitor {
  let source: Source.File
  let severity: Diagnostic.Severity
  let converter: SourceLocationConverter
  let layer: Swift.Int
  var matches: [Diagnostic.Record] = []

  init(
    source: Source.File,
    severity: Diagnostic.Severity,
    converter: SourceLocationConverter,
    layer: Swift.Int
  ) {
    self.source = source
    self.severity = severity
    self.converter = converter
    self.layer = layer
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
      member.declName.baseName.text == "package",
      let argument = node.arguments.first(where: { $0.label?.text == "url" }),
      let literal = argument.expression.as(StringLiteralExprSyntax.self),
      let url = manifestStringLiteralText(literal),
      let target = manifestLayer(ofURL: url),
      target > layer
    else {
      return .visitChildren
    }
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
        identifier: "upward layer edge",
        message: "[upward layer edge] [PACKAGE-LAYER-DIRECTION]: a \(manifestLayerNames[layer] ?? "") "
          + "package must not depend on the \(manifestLayerNames[target] ?? "") layer (`\(url)`); "
          + "atoms depend on atoms, molecules on atoms and molecules, standards on atoms, "
          + "molecules and standards, compositions on every layer."
      )
    )
    return .visitChildren
  }
}
