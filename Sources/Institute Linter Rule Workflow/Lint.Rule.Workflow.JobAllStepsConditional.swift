public import Lint

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
        observe: Lint.Rule.measured { _, _ in [] }
    )
}
