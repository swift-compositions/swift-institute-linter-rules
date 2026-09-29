public import Lint
internal import SwiftSyntax

extension Lint.Rule {
  public static let `comment in source` = Lint.Rule(
    id: "comment in source",
    default: .warning,
    controls: [
      .init(
        id: "comment in source line",
        source: "// Implementation note\nstruct Value {}",
        path: "Sources/Structure Core/Value.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "comment in source documentation",
        source: "/// A value.\nstruct Value {}",
        path: "Sources/Structure Core/Value.swift",
        expectation: .findings(1)
      ),
      .init(
        id: "comment in source block and trailing",
        source: "/* block */\nlet value = 1 // trailing",
        path: "Sources/Structure Core/Value.swift",
        expectation: .findings(2)
      ),
      .init(
        id: "comment in source directive",
        source: "// swift-linter:disable:next comment in source\nstruct Value {}",
        path: "Sources/Structure Core/Value.swift",
        expectation: .clean
      ),
      .init(
        id: "comment in source string",
        source: "let text = \"// not a comment\"",
        path: "Sources/Structure Core/Value.swift",
        expectation: .clean
      ),
      .init(
        id: "comment in source test",
        source: "// Test note\nstruct Value {}",
        path: "Tests/Structure Core Tests/Value.swift",
        expectation: .clean
      ),
    ],
    observe: Lint.Rule.measured { source, severity in
      let path = source.file.filePath
      guard path.hasPrefix("Sources/") || path.contains("/Sources/") else {
        return []
      }
      let visitor = StructureCommentInSourceVisitor(
        source: source.file,
        severity: severity,
        converter: source.converter
      )
      visitor.walk(source.tree)
      return visitor.matches
    }
  )
}

@usableFromInline
internal let structureCommentInSourceMessage: Swift.String =
  "[comment in source] [SOURCE-NO-COMMENTS]: sources carry no `//`, `///` or "
  + "`/* */` comments; names, types and tests carry the meaning. Only "
  + "`// swift-linter:` directives are admitted."

internal final class StructureCommentInSourceVisitor: SyntaxVisitor {
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

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    scan(token.leadingTrivia, from: token.position)
    scan(token.trailingTrivia, from: token.endPositionBeforeTrailingTrivia)
    return .visitChildren
  }

  private func scan(_ trivia: Trivia, from start: AbsolutePosition) {
    var position = start
    for piece in trivia {
      defer { position = position.advanced(by: piece.sourceLength.utf8Length) }
      let text: Swift.String? =
        switch piece {
        case .lineComment(let text): text
        case .docLineComment(let text), .blockComment(let text), .docBlockComment(let text): text
        default: nil
        }
      guard let text, !text.hasPrefix("// swift-linter:") else { continue }
      let location = converter.location(for: position)
      matches.append(
        Diagnostic.Record(
          location: Source.Location(
            fileID: source.fileID,
            filePath: source.filePath,
            line: location.line,
            column: location.column
          ),
          severity: severity,
          identifier: "comment in source",
          message: structureCommentInSourceMessage
        )
      )
    }
  }
}
