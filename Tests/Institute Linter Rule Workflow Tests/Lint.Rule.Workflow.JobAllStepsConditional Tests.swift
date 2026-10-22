import Byte
import File_System_Test_Support
import Lint
import Linter_Rules_Test_Support
import SwiftParser
import Testing

@testable import Institute_Linter_Rule_Workflow

extension Lint.Rule {
    @Suite
    struct `workflow job all steps conditional Tests` {
        @Suite struct Unit {}
        @Suite struct Integration {}
    }
}

extension Lint.Rule.`workflow job all steps conditional Tests` {
    static func findings(in workflow: Swift::String) -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(
            from: workflow,
            file: ".github/workflows/fixture.yml"
        )
        return Lint.Rule.`workflow job all steps conditional`.observe(parsed, .warning).findings
    }
}

extension Lint.Rule.`workflow job all steps conditional Tests`.Unit {
    @Test
    func `a job whose every step is conditional is flagged`() {
        let findings = Lint.Rule.`workflow job all steps conditional Tests`.findings(
            in: """
                jobs:
                  lint:
                    runs-on: ubuntu-latest
                    steps:
                      - if: ${{ needs.detect.outputs.run == 'true' }}
                        run: swift run lint
                      - if: ${{ always() }}
                        uses: actions/upload-artifact@v4
                """
        )
        #expect(findings.count == 1)
        #expect(findings.first?.severity == .warning)
        #expect(
            findings.first?.message
                == "[workflow job all steps conditional]: job 'lint' has no job-level `if:` "
                + "and every one of its 2 steps has its own `if:`"
        )
    }

    @Test
    func `a job level condition is lawful`() {
        let findings = Lint.Rule.`workflow job all steps conditional Tests`.findings(
            in: """
                jobs:
                  lint:
                    if: ${{ needs.detect.outputs.run == 'true' }}
                    runs-on: ubuntu-latest
                    steps:
                      - run: swift run lint
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `an unconditional step is lawful`() {
        let findings = Lint.Rule.`workflow job all steps conditional Tests`.findings(
            in: """
                jobs:
                  lint:
                    runs-on: ubuntu-latest
                    steps:
                      - if: ${{ needs.detect.outputs.run == 'true' }}
                        run: swift run lint
                      - run: assert-lint-ran
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `a nested condition does not exempt the job`() {
        let findings = Lint.Rule.`workflow job all steps conditional Tests`.findings(
            in: """
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
                """
        )
        #expect(findings.count == 1)
    }
}

extension Lint.Rule.`workflow job all steps conditional Tests`.Integration {
    @Test
    func `the root manifest discovers workflow files`() throws {
        try File.Directory.temporary { root in
            let manifest = root.path / "Package.swift"
            let violation = root.path / ".github" / "workflows" / "violation.yml"
            let lawful = root.path / ".github" / "workflows" / "lawful.yaml"
            try File.System.Write.Atomic.write(
                [Byte](utf8: "import PackageDescription\nlet package = Package(name: \"Fixture\")"),
                to: manifest
            )
            try File.System.Write.Atomic.write(
                [Byte](
                    utf8: """
                        jobs:
                          lint:
                            runs-on: ubuntu-latest
                            steps:
                              - if: ${{ always() }}
                                run: swift run lint
                        """
                ),
                to: violation,
                createIntermediates: true
            )
            try File.System.Write.Atomic.write(
                [Byte](
                    utf8: """
                        jobs:
                          test:
                            runs-on: ubuntu-latest
                            steps:
                              - run: swift test
                        """
                ),
                to: lawful
            )
            let parsed = Lint.Source.parsed(
                from: "import PackageDescription\nlet package = Package(name: \"Fixture\")",
                file: manifest.description,
                path: Lint.Source.Path("Package.swift")
            )
            let findings = Lint.Rule.`workflow job all steps conditional`.observe(
                parsed,
                .warning
            ).findings
            #expect(findings.count == 1)
            #expect(findings.first?.location.filePath == violation.description)
        }
    }
}
