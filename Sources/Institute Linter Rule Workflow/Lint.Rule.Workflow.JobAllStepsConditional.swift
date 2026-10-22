internal import Byte
internal import Either
internal import File_System_Core
public import Lint
internal import Paths
internal import SwiftSyntax

extension Lint.Rule {
    public static let `workflow job all steps conditional` = Lint.Rule(
        id: "workflow job all steps conditional",
        default: .warning,
        controls: [
            .init(
                id: "workflow job all steps conditional violation",
                source: """
                    jobs:
                      lint:
                        runs-on: ubuntu-latest
                        steps:
                          - if: ${{ needs.detect.outputs.run == 'true' }}
                            run: swift run lint
                          - if: ${{ always() }}
                            run: report
                    """,
                path: ".github/workflows/violation.yml",
                expectation: .findings(1)
            ),
            .init(
                id: "workflow job all steps conditional job condition",
                source: """
                    jobs:
                      lint:
                        if: ${{ needs.detect.outputs.run == 'true' }}
                        runs-on: ubuntu-latest
                        steps:
                          - run: swift run lint
                    """,
                path: ".github/workflows/lawful.yml",
                expectation: .clean
            ),
            .init(
                id: "workflow job all steps conditional nested condition near miss",
                source: """
                    jobs:
                      lint:
                        strategy:
                          if: ${{ needs.detect.outputs.run == 'true' }}
                          matrix:
                            os: [ubuntu-latest]
                        runs-on: ${{ matrix.os }}
                        steps:
                          - if: ${{ matrix.os == 'ubuntu-latest' }}
                            run: swift run lint
                    """,
                path: ".github/workflows/near-miss.yaml",
                expectation: .findings(1)
            ),
        ],
        observe: Lint.Rule.measured { source, severity in
            workflowJobAllStepsConditionalFindings(source: source, severity: severity)
        }
    )
}

internal func workflowJobAllStepsConditionalFindings(
    source: borrowing Lint.Source.Parsed,
    severity: Diagnostic.Severity
) -> [Diagnostic.Record] {
    let path = source.path.underlying
    if workflowJobAllStepsConditionalIsWorkflowPath(path) {
        return workflowJobAllStepsConditionalFindings(
            in: source.tree.description,
            fileID: source.file.fileID,
            filePath: source.file.filePath,
            severity: severity
        )
    }
    guard path == "Package.swift" else { return [] }
    return workflowJobAllStepsConditionalPackageFindings(source: source, severity: severity)
}

private func workflowJobAllStepsConditionalPackageFindings(
    source: borrowing Lint.Source.Parsed,
    severity: Diagnostic.Severity
) -> [Diagnostic.Record] {
    let manifest = source.file.filePath
    guard let boundary = manifest.lastIndex(where: { $0 == "/" || $0 == "\\" })
    else { return [] }

    let directory: File.Directory
    do throws(Paths.Path.Error) {
        directory = try File.Directory(
            validating: Swift.String(manifest[..<boundary]) + "/.github/workflows"
        )
    } catch {
        return []
    }

    let entries: [File.Directory.Entry]
    do throws(File.Directory.Contents.Error) {
        entries = try File.Directory.Contents.list(at: directory)
    } catch {
        return []
    }

    return entries.compactMap { entry -> (Swift.String, File.Path)? in
        guard case .file = entry.type else { return nil }
        guard let name = Swift.String(entry.name),
            workflowJobAllStepsConditionalHasWorkflowExtension(name),
            let path = entry.pathIfValid
        else { return nil }
        return (name, path)
    }
    .sorted(by: { $0.0 < $1.0 })
    .flatMap { (_, path) -> [Diagnostic.Record] in
        guard let contents = workflowJobAllStepsConditionalRead(path) else { return [] }
        return workflowJobAllStepsConditionalFindings(
            in: contents,
            fileID: path.description,
            filePath: path.description,
            severity: severity
        )
    }
}

private func workflowJobAllStepsConditionalRead(_ path: borrowing File.Path) -> Swift.String? {
    do throws(Either<File.System.Read.Full.Error, Never>) {
        return try File.System.Read.Full.read(from: path) { span in
            span.withUnsafeBytes { buffer in
                unsafe Swift.String(decoding: [Swift.UInt8](buffer), as: Swift.UTF8.self)
            }
        }
    } catch {
        return nil
    }
}

private func workflowJobAllStepsConditionalHasWorkflowExtension(
    _ path: Swift.String
) -> Swift.Bool {
    path.hasSuffix(".yml") || path.hasSuffix(".yaml")
}

private func workflowJobAllStepsConditionalIsWorkflowPath(_ path: Swift.String) -> Swift.Bool {
    guard workflowJobAllStepsConditionalHasWorkflowExtension(path) else { return false }
    let components = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
    let tail = components.suffix(3)
    guard tail.count == 3 else { return false }
    return tail[tail.startIndex] == ".github"
        && tail[tail.index(after: tail.startIndex)] == "workflows"
}

internal func workflowJobAllStepsConditionalFindings(
    in workflow: Swift.String,
    fileID: Swift.String,
    filePath: Swift.String,
    severity: Diagnostic.Severity
) -> [Diagnostic.Record] {
    let lines = workflowJobAllStepsConditionalLines(workflow)
    guard
        let jobsIndex = lines.firstIndex(where: {
            $0.indent == 0 && workflowJobAllStepsConditionalKey($0.content) == "jobs"
                && workflowJobAllStepsConditionalHasBlockValue($0.content)
        })
    else { return [] }

    let jobsIndent = lines[jobsIndex].indent
    let jobsEnd =
        lines[(jobsIndex + 1)...].firstIndex(where: { $0.indent <= jobsIndent })
        ?? lines.endIndex
    let jobLines = lines[(jobsIndex + 1)..<jobsEnd]
    guard let jobIndent = jobLines.map({ $0.indent }).min() else { return [] }
    let starts = jobLines.indices.filter {
        jobLines[$0].indent == jobIndent
            && workflowJobAllStepsConditionalKey(jobLines[$0].content) != nil
            && workflowJobAllStepsConditionalHasBlockValue(jobLines[$0].content)
    }

    return starts.enumerated().compactMap { offset, start in
        let end = offset + 1 < starts.count ? starts[offset + 1] : jobsEnd
        let job = lines[start]
        guard let name = workflowJobAllStepsConditionalKey(job.content) else { return nil }
        let body = lines[(start + 1)..<end]
        guard let directIndent = body.map({ $0.indent }).min() else { return nil }
        if body.contains(where: {
            $0.indent == directIndent && workflowJobAllStepsConditionalKey($0.content) == "if"
        }) {
            return nil
        }
        guard
            let stepsIndex = body.firstIndex(where: {
                $0.indent == directIndent
                    && workflowJobAllStepsConditionalKey($0.content) == "steps"
                    && workflowJobAllStepsConditionalHasBlockValue($0.content)
            })
        else { return nil }
        let stepsEnd =
            lines[(stepsIndex + 1)..<end].firstIndex(where: {
                $0.indent <= directIndent
            }) ?? end
        let steps = lines[(stepsIndex + 1)..<stepsEnd]
        guard let stepIndent = steps.filter({ $0.content.hasPrefix("-") }).map({ $0.indent }).min()
        else { return nil }
        let stepStarts = steps.indices.filter {
            steps[$0].indent == stepIndent && steps[$0].content.hasPrefix("-")
        }
        guard !stepStarts.isEmpty,
            stepStarts.enumerated().allSatisfy({ stepOffset, stepStart in
                let stepEnd =
                    stepOffset + 1 < stepStarts.count
                    ? stepStarts[stepOffset + 1]
                    : stepsEnd
                return workflowJobAllStepsConditionalStepHasIf(
                    lines: lines,
                    start: stepStart,
                    end: stepEnd
                )
            })
        else { return nil }

        return Diagnostic.Record(
            location: Source.Location(
                fileID: fileID,
                filePath: filePath,
                line: job.number,
                column: job.indent + 1
            ),
            severity: severity,
            identifier: "workflow job all steps conditional",
            message: "[workflow job all steps conditional]: job '\(name)' has no job-level `if:` "
                + "and every one of its \(stepStarts.count) steps has its own `if:`"
        )
    }
}

private func workflowJobAllStepsConditionalLines(
    _ workflow: Swift.String
) -> [(number: Swift.Int, indent: Swift.Int, content: Swift.Substring)] {
    workflow.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap {
        offset, raw in
        let line = raw.last == "\r" ? raw.dropLast() : raw[...]
        let indent = line.prefix(while: { $0 == " " }).count
        let content = line.dropFirst(indent)
        guard !content.isEmpty, !content.hasPrefix("#"), !content.hasPrefix("\t")
        else { return nil }
        return (number: offset + 1, indent: indent, content: content)
    }
}

private func workflowJobAllStepsConditionalKey(
    _ content: Swift.Substring
) -> Swift.String? {
    var quote: Swift.Character?
    var escaped = false
    for index in content.indices {
        let character = content[index]
        if escaped {
            escaped = false
            continue
        }
        if character == "\\", quote == "\"" {
            escaped = true
            continue
        }
        if character == "\"" || character == "'" {
            if quote == character {
                quote = nil
            } else if quote == nil {
                quote = character
            }
            continue
        }
        guard character == ":", quote == nil else { continue }
        var key = content[..<index].drop(while: { $0 == " " })
        while key.last == " " { key = key.dropLast() }
        if key.count >= 2,
            let first = key.first,
            key.last == first,
            first == "\"" || first == "'"
        {
            key = key.dropFirst().dropLast()
        }
        return key.isEmpty ? nil : Swift.String(key)
    }
    return nil
}

private func workflowJobAllStepsConditionalHasBlockValue(
    _ content: Swift.Substring
) -> Swift.Bool {
    guard let colon = content.firstIndex(of: ":") else { return false }
    let value = content[content.index(after: colon)...].drop(while: { $0 == " " })
    return value.isEmpty || value.hasPrefix("#")
}

private func workflowJobAllStepsConditionalStepHasIf(
    lines: [(number: Swift.Int, indent: Swift.Int, content: Swift.Substring)],
    start: Swift.Int,
    end: Swift.Int
) -> Swift.Bool {
    let step = lines[start]
    let afterDash = step.content.dropFirst()
    let spaces = afterDash.prefix(while: { $0 == " " }).count
    let inline = afterDash.dropFirst(spaces)
    if workflowJobAllStepsConditionalKey(inline) == "if" { return true }
    let directIndent: Swift.Int
    if !inline.isEmpty {
        directIndent = step.indent + 1 + spaces
    } else {
        guard let continuationIndent = lines[(start + 1)..<end].map({ $0.indent }).min()
        else { return false }
        directIndent = continuationIndent
    }
    return lines[(start + 1)..<end].contains {
        $0.indent == directIndent && workflowJobAllStepsConditionalKey($0.content) == "if"
    }
}
