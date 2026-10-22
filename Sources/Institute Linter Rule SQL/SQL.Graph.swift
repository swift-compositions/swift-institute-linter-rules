internal import File_System
internal import Lint
internal import SwiftParser
internal import SwiftSyntax

extension SQL {
    internal struct Graph {
        private let executable: Swift::Set<Swift::String>
        private let sourceRoots: [Swift::String: Swift::String]
        private let targets: Swift::Set<Swift::String>

        internal init(_ tree: SourceFileSyntax) {
            let visitor = SQL.Graph.Visitor(tree)
            executable = visitor.executableProductTargets.union(visitor.executableTargets)
            sourceRoots = visitor.sourceRoots
            targets = visitor.targets
        }
    }
}

extension SQL.Graph {
    internal func isLibrary(sourcePath: Swift::String) -> Swift::Bool {
        let path = sourcePath.replacing("\\", with: "/")
        let explicit =
            sourceRoots
            .filter { path == $0.value || path.hasPrefix($0.value + "/") }
            .max { $0.value.count < $1.value.count }?
            .key
        let target = explicit ?? defaultTarget(path)
        guard let target, targets.contains(target) else { return false }
        return !executable.contains(target)
    }

    private func defaultTarget(_ path: Swift::String) -> Swift::String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 3, components[0] == "Sources" else { return nil }
        return Swift::String(components[1])
    }
}

extension SQL.Graph {
    internal static func load(for source: borrowing Lint.Source.Parsed) -> Self? {
        guard source.file.filePath != source.path.underlying else { return nil }
        let absolute: File.Path
        do throws(File.Path.Error) {
            absolute = try File.Path(source.file.filePath)
        } catch {
            return nil
        }
        var root = absolute
        for _ in source.path.underlying.split(separator: "/", omittingEmptySubsequences: true) {
            guard let parent = root.parent else { return nil }
            root = parent
        }
        let text: Swift::String?
        do throws(Either<File.System.Read.Full.Error, Never>) {
            text = try contents(of: File(root / "Package.swift"))
        } catch {
            return nil
        }
        guard let text else { return nil }
        return Self(Parser.parse(source: text))
    }

    private static func contents(
        of file: File
    ) throws(Either<File.System.Read.Full.Error, Never>) -> Swift::String? {
        try file.read.full { span in
            var bytes: [Byte] = []
            bytes.reserveCapacity(span.count)
            for index in span.indices { bytes.append(span[index]) }
            return Swift::String(validating: bytes, as: Swift::UTF8.self)
        }
    }
}
