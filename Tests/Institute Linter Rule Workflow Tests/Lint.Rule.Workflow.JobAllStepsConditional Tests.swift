import Lint
import Linter_Rules_Test_Support
import SwiftParser
import Testing

@testable import Institute_Linter_Rule_Workflow

extension Lint.Rule {
    @Suite
    struct `workflow job all steps conditional Tests` {
        @Suite struct Unit {}
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
