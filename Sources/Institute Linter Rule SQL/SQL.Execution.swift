public import Lint
internal import SwiftSyntax

extension SQL {
    internal enum Execution {}
}

extension Lint.Rule {
    public static let `sql execution in library target` = Lint.Rule(
        id: "sql execution in library target",
        default: .warning,
        controls: [
            .init(
                id: "sql execution in library target violation",
                source: "func records() throws { try database.fetchAll(query) }",
                path: "Sources/Records/Records.swift",
                expectation: .findings(1)
            ),
            .init(
                id: "sql execution in app target lawful",
                source: "func records() throws { try database.fetchAll(query) }",
                path: "Laurie/Records.swift",
                expectation: .clean
            ),
            .init(
                id: "sql execution app named library near miss",
                source: "func save() throws { try database.execute(statement) }",
                path: "Sources/Laurie App/Save.swift",
                expectation: .findings(1)
            ),
        ],
        observe: { source, severity in
            let isLibrary =
                SQL.Graph.load(for: source)?.isLibrary(
                    sourcePath: source.path.underlying
                ) ?? sqlExecutionHasConventionalLibraryPath(source.path.underlying)
            guard isLibrary else {
                return Lint.Rule.Observation(findings: [], coverage: .measured)
            }
            let visitor = SQL.Execution.Visitor(
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
internal let sqlExecutionInLibraryTargetMessage: Swift::String =
    "[sql execution in library target]: `fetchAll`, `fetchOne`, `fetchCount`, "
    + "`fetchSet`, and `execute` calls are permitted only in executable and app "
    + "targets; return a SQL statement or query value from library targets and "
    + "execute it at the edge."

private func sqlExecutionHasConventionalLibraryPath(_ path: Swift::String) -> Swift::Bool {
    let components = path.replacing("\\", with: "/")
        .split(separator: "/", omittingEmptySubsequences: true)
    return components.count >= 3 && components[0] == "Sources"
}
