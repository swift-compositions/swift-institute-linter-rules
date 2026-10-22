import Foundation
import Lint
import Linter_Rule_Package
import Linter_Rules
import Linter_Rules_Test_Support
import Testing

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)
    extension Lint.Rule {
        @Suite
        struct `target import edge contract Tests` {
            @Suite struct Unit {}
            @Suite struct `Edge Case` {}
            @Suite struct Integration {}
        }
    }

    extension Lint.Rule.`target import edge contract Tests` {
        struct Fixture {
            let root: URL

            init(manifest: Swift::String, files: [Swift::String: Swift::String]) throws {
                root = FileManager.default.temporaryDirectory
                    .appending(path: "target-import-edge-\(UUID())")
                try Self.write(manifest, to: root.appending(path: "Package.swift"))
                for (path, contents) in files {
                    try Self.write(contents, to: root.appending(path: path))
                }
            }
        }
    }

    extension Lint.Rule.`target import edge contract Tests`.Fixture {
        fileprivate static func write(_ contents: Swift::String, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        fileprivate func remove() {
            try! FileManager.default.removeItem(at: root)
        }

        fileprivate func findings() throws -> [Diagnostic.Record] {
            let manifest = try Swift::String(
                contentsOf: root.appending(path: "Package.swift"),
                encoding: .utf8
            )
            let parsed = Lint.Source.parsed(
                from: manifest,
                file: root.appending(path: "Package.swift").path,
                path: Lint.Source.Path("Package.swift")
            )
            return Lint.Rule.`target import edge`.observe(parsed, .warning).findings
        }
    }

    extension Lint.Rule.`target import edge contract Tests` {
        static func manifest(
            targets: Swift::String,
            dependencies: Swift::String = ""
        ) -> Swift::String {
            """
            // swift-tools-version: 6.4
            import PackageDescription

            let package = Package(
                name: "fixture",
                dependencies: [\(dependencies)],
                targets: [\(targets)]
            )
            """
        }
    }

    extension Lint.Rule.`target import edge contract Tests`.Unit {
        @Test
        func `an imported same-package module without a direct dependency fires`() throws {
            let fixture = try Lint.Rule.`target import edge contract Tests`.Fixture(
                manifest: Lint.Rule.`target import edge contract Tests`.manifest(
                    targets: """
                        .target(name: "Consumer"),
                        .target(name: "Dependency"),
                        """
                ),
                files: ["Sources/Consumer/Consumer.swift": "import Dependency\n"]
            )
            defer { fixture.remove() }
            let findings = try fixture.findings()
            #expect(findings.count == 1)
            #expect(
                findings.first?.message
                    == "[target import edge]: Sources/Consumer/Consumer.swift:1: target "
                    + "'Consumer' imports 'Dependency' without a declared dependency edge "
                    + "([TARGET-IMPORT-EDGE]: transitive-build riding is a scheduling race; "
                    + "declare the target/product dependency)"
            )
        }
    }

    extension Lint.Rule.`target import edge contract Tests`.`Edge Case` {
        @Test
        func `an imported module exposed by the declared product is lawful`() throws {
            let fixture = try Lint.Rule.`target import edge contract Tests`.Fixture(
                manifest: Lint.Rule.`target import edge contract Tests`.manifest(
                    targets: """
                        .target(
                            name: "Consumer",
                            dependencies: [.product(name: "Library", package: "dependency")]
                        ),
                        """,
                    dependencies: #".package(path: "Dependency")"#
                ),
                files: [
                    "Sources/Consumer/Consumer.swift": "import Dependency\n",
                    "Dependency/Package.swift": """
                    // swift-tools-version: 6.4
                    import PackageDescription
                    let package = Package(
                        name: "dependency",
                        products: [.library(name: "Library", targets: ["Dependency"])],
                        targets: [.target(name: "Dependency")]
                    )
                    """,
                ]
            )
            defer { fixture.remove() }
            #expect(try fixture.findings().isEmpty)
        }

        @Test
        func `a transitive product module remains undeclared and fires`() throws {
            let fixture = try Lint.Rule.`target import edge contract Tests`.Fixture(
                manifest: Lint.Rule.`target import edge contract Tests`.manifest(
                    targets: """
                        .target(
                            name: "Consumer",
                            dependencies: [.product(name: "Facade", package: "dependency")]
                        ),
                        """,
                    dependencies: #".package(path: "Dependency")"#
                ),
                files: [
                    "Sources/Consumer/Consumer.swift": "#if canImport(Transitive)\nimport Transitive\n#endif\n",
                    "Dependency/Package.swift": """
                    // swift-tools-version: 6.4
                    import PackageDescription
                    let package = Package(
                        name: "dependency",
                        products: [
                            .library(name: "Facade", targets: ["Facade"]),
                            .library(name: "Transitive", targets: ["Transitive"]),
                        ],
                        targets: [.target(name: "Facade"), .target(name: "Transitive")]
                    )
                    """,
                ]
            )
            defer { fixture.remove() }
            let findings = try fixture.findings()
            #expect(findings.count == 1)
            #expect(findings.first?.message.contains("imports 'Transitive'") == true)
        }
    }

    extension Lint.Rule.`target import edge contract Tests`.Integration {
        @Test
        func `the fifty-seven issue 154 targets are all reported`() throws {
            let names = (1...57).map { "Issue154Target\($0)" }
            let targets = names.map {
                ".target(name: \"\($0)\", dependencies: [.product(name: \"Facade\", package: \"dependency\")])"
            }.joined(separator: ",\n")
            var files = Swift.Dictionary(
                uniqueKeysWithValues: names.map {
                    ("Sources/\($0)/\($0).swift", "import SwiftSyntax\n")
                }
            )
            files["Dependency/Package.swift"] = """
                // swift-tools-version: 6.4
                import PackageDescription
                let package = Package(
                    name: "dependency",
                    products: [
                        .library(name: "Facade", targets: ["Facade"]),
                        .library(name: "SwiftSyntax", targets: ["SwiftSyntax"]),
                    ],
                    targets: [.target(name: "Facade"), .target(name: "SwiftSyntax")]
                )
                """
            let fixture = try Lint.Rule.`target import edge contract Tests`.Fixture(
                manifest: Lint.Rule.`target import edge contract Tests`.manifest(
                    targets: targets,
                    dependencies: #".package(path: "Dependency")"#
                ),
                files: files
            )
            defer { fixture.remove() }
            #expect(try fixture.findings().count == 57)
        }
    }
#endif
