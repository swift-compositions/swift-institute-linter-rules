public import Lint
internal import SwiftSyntax

extension Lint.Rule {
  public static let `comment in source` = Lint.Rule(
    id: "comment in source",
    default: .warning,
    controls: [
      .init(
        id: "comment in source required reason",
        source: "// swift-linter:disable:next example\n// REASON: SDK contract.\nlet value = 1",
        path: "Sources/Structure Core/Value.swift",
        expectation: .clean
      ),
      .init(
        id: "comment in source unassociated reason",
        source: "// REASON: Ordinary comment.\nlet value = 1",
        path: "Sources/Structure Core/Value.swift",
        expectation: .findings(1)
      ),
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
        converter: source.converter,
        metadata: structureCommentInSourceMetadata(source.tree, converter: source.converter)
      )
      visitor.walk(source.tree)
      return visitor.matches
    },
    repair: { source in
      let path = source.file.filePath
      guard path.hasPrefix("Sources/") || path.contains("/Sources/") else {
        return .unchanged
      }
      let original = source.tree.description
      let contents = StructureCommentInSourceRewriter(
        metadata: structureCommentInSourceMetadata(source.tree, converter: source.converter)
      )
        .rewrite(Syntax(source.tree)).description
      return contents == original
        ? .unchanged
        : .edits([.rewrite(path: source.path, contents: contents)])
    }
  )
}

@usableFromInline
internal let structureCommentInSourceMessage: Swift::String =
  "[comment in source] [SOURCE-NO-COMMENTS]: sources carry no `//`, `///` or "
  + "`/* */` comments; names, types and tests carry the meaning. Only "
  + "`// swift-linter:` directives and their required adjacent `// REASON:` metadata are admitted."

internal final class StructureCommentInSourceVisitor: SyntaxVisitor {
  let source: Source.File
  let severity: Diagnostic.Severity
  let converter: SourceLocationConverter
  var matches: [Diagnostic.Record] = []
  let metadata: Set<Int>

  init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter, metadata: Set<Int>) {
    self.metadata = metadata
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
      let text: Swift::String? =
        switch piece {
        case .lineComment(let text): text
        case .docLineComment(let text), .blockComment(let text), .docBlockComment(let text): text
        default: nil
        }
      guard let text, !text.hasPrefix("// swift-linter:"), !metadata.contains(position.utf8Offset) else { continue }
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

internal final class StructureCommentInSourceRewriter: SyntaxRewriter {
  let metadata: Set<Int>

  init(metadata: Set<Int>) {
    self.metadata = metadata
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ token: TokenSyntax) -> TokenSyntax {
    token
      .with(\.leadingTrivia, stripped(token.leadingTrivia, leading: true, from: token.position))
      .with(\.trailingTrivia, stripped(token.trailingTrivia, leading: false, from: token.endPositionBeforeTrailingTrivia))
  }

  private func stripped(_ trivia: Trivia, leading: Swift::Bool, from start: AbsolutePosition) -> Trivia {
    var position = start
    var pieces: [TriviaPiece] = []
    var skipNewline = false
    for piece in trivia {
      defer { position = position.advanced(by: piece.sourceLength.utf8Length) }
      if skipNewline {
        skipNewline = false
        switch piece {
        case .newlines(let count):
          if count > 1 { pieces.append(.newlines(count - 1)) }
          continue
        case .carriageReturnLineFeeds(let count):
          if count > 1 { pieces.append(.carriageReturnLineFeeds(count - 1)) }
          continue
        default:
          break
        }
      }
      guard !metadata.contains(position.utf8Offset), structureCommentInSourceIsRemovable(piece) else {
        pieces.append(piece)
        continue
      }
      while let last = pieces.last, last.isSpaceOrTab {
        pieces.removeLast()
      }
      skipNewline = leading && (pieces.last.map(\.isNewline) ?? true)
    }
    return Trivia(pieces: pieces)
  }
}

internal func structureCommentInSourceIsRemovable(_ piece: TriviaPiece) -> Swift::Bool {
  switch piece {
  case .lineComment(let text): !text.hasPrefix("// swift-linter:")
  case .docLineComment, .blockComment, .docBlockComment: true
  default: false
  }
}

extension TriviaPiece {
  fileprivate var isSpaceOrTab: Swift::Bool {
    switch self {
    case .spaces, .tabs: true
    default: false
    }
  }
}

internal func structureCommentInSourceMetadata(
  _ tree: SourceFileSyntax,
  converter: SourceLocationConverter
) -> Set<Int> {
  var comments: [(text: String, position: AbsolutePosition, line: Int)] = []
  for token in tree.tokens(viewMode: .sourceAccurate) {
    for (trivia, start) in [(token.leadingTrivia, token.position), (token.trailingTrivia, token.endPositionBeforeTrailingTrivia)] {
      var position = start
      for piece in trivia {
        defer { position = position.advanced(by: piece.sourceLength.utf8Length) }
        guard case .lineComment(let text) = piece else { continue }
        comments.append((text, position, converter.location(for: position).line))
      }
    }
  }
  var metadata: Set<Int> = []
  let prefixes = ["// swift-linter:disable:next ", "// swift-linter:disable:line "]
  for (directive, reason) in zip(comments, comments.dropFirst()) {
    guard reason.line == directive.line + 1,
      let prefix = prefixes.first(where: directive.text.hasPrefix),
      directive.text.dropFirst(prefix.count).contains(where: { !$0.isWhitespace }),
      reason.text.hasPrefix("// REASON:"),
      reason.text.dropFirst("// REASON:".count).contains(where: { !$0.isWhitespace })
    else { continue }
    metadata.insert(reason.position.utf8Offset)
  }
  return metadata
}
