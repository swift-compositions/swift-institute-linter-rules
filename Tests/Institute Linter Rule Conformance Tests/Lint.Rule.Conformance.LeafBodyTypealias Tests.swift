// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-institute-linter-rules open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-institute-linter-rules project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Lint
import Linter_Rules_Test_Support
import SwiftParser
import SwiftSyntax
import Testing

@testable import Institute_Linter_Rule_Conformance

extension Lint.Rule {
  @Suite
  struct `leaf body typealias missing Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
  }
}

extension Lint.Rule.`leaf body typealias missing Tests` {
  static func findings(in source: String, file: String = "test.swift") -> [Diagnostic.Record] {
    let parsed = Lint.Source.parsed(from: source, file: file)
    return Lint.Rule.`leaf body typealias missing`.observe(parsed, .warning).findings
  }
}

extension Lint.Rule.`leaf body typealias missing Tests`.Unit {
  @Test
  func `generic Parser leaf conformer without typealias is flagged`() {
    let source = """
      extension Binary.LEB128.Unsigned: Parser.`Protocol` {
          public typealias Input = ArraySlice<UInt8>
          public typealias Output = T
          public typealias Failure = Binary.LEB128.Error
          public func parse(_ input: inout Input) throws(Failure) -> T {
              fatalError()
          }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    let count = findings.count
    #expect(count == 1)
    if count == 1 {
      #expect(findings[0].identifier == "leaf body typealias missing")
      #expect(findings[0].severity == .warning)
    }
  }

  @Test
  func `generic Serializer leaf conformer without typealias is flagged`() {
    let source = """
      extension Binary.LEB128.Signed: Serializer.`Protocol` {
          public typealias Output = T
          public typealias Buffer = [UInt8]
          public typealias Failure = Never
          public func serialize(_ value: T, into buffer: inout [UInt8]) {}
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }

  @Test
  func `Coder leaf conformer without typealias is flagged`() {
    let source = """
      extension Binary.Coder: Coder.`Protocol` {
          public typealias Input = ArraySlice<Byte>
          public typealias Output = Foo
          public typealias Buffer = [UInt8]
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Output { fatalError() }
          public func serialize(_ output: Output, into buffer: inout [UInt8]) {}
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }

  @Test
  func `multiple leaf conformers in one file are all flagged`() {
    let source = """
      extension A: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      extension B: Serializer.`Protocol` {
          public typealias Output = Int
          public typealias Buffer = [UInt8]
          public typealias Failure = Never
          public func serialize(_ value: Int, into buffer: inout [UInt8]) {}
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 2)
  }

  @Test
  func `struct-declared conformance (not extension) without typealias is flagged`() {
    // The conformance can be declared on the type's own decl rather
    // than an extension — same link-time failure, must still fire.
    let source = """
      public struct MyParser: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }

  @Test
  func `class-declared conformance without typealias is flagged`() {
    let source = """
      public final class MyCoder: Coder.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Buffer = [UInt8]
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
          public func serialize(_ output: Int, into buffer: inout [UInt8]) {}
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }

  @Test
  func `module-qualified Parser conformance still flagged`() {
    let source = """
      extension X: Parser_Core.Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }
}

extension Lint.Rule.`leaf body typealias missing Tests`.`Edge Case` {
  @Test
  func `leaf conformer with typealias Body equals Never is NOT flagged`() {
    let source = """
      extension Binary.LEB128.Unsigned: Parser.`Protocol` {
          public typealias Input = ArraySlice<UInt8>
          public typealias Output = T
          public typealias Failure = Binary.LEB128.Error
          public typealias Body = Never
          public func parse(_ input: inout Input) throws(Failure) -> T {
              fatalError()
          }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `leaf conformer with typealias Body equals Swift dot Never is NOT flagged`() {
    let source = """
      extension X: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public typealias Body = Swift.Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `non-leaf conformer with body property is NOT flagged`() {
    // Declarative shape: body returns another Parser. Body is inferred from
    // the body property's return type; explicit typealias not required.
    let source = """
      extension MyParser: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public var body: some Parser.`Protocol` {
              Binary.LEB128.Unsigned<Int>()
          }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `extension on the protocol itself is NOT flagged`() {
    // `extension Parser.\`Protocol\` where ...` extends the protocol; its
    // inheritance clause is empty (or contains protocol refinements, not
    // leaf-body protocols). The rule fires on conformance, not extension.
    let source = """
      extension Parser.`Protocol` where Self: ~Copyable, Body == Never {
          public var body: Never { fatalError() }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `extension without inheritance clause is NOT flagged`() {
    let source = """
      extension MyType {
          public func compute() -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `extension conforming to other protocol is NOT flagged`() {
    let source = """
      extension Foo: Sendable {}
      extension Bar: CustomStringConvertible {
          public var description: String { "bar" }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `mixed conformance with Sendable AND Parser still flagged when typealias missing`() {
    let source = """
      extension X: Sendable, Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }

  @Test
  func `conformance and body split across two extensions is NOT flagged`() {
    // The Structure pack's own split-extension idiom: one extension
    // declares the conformance, another (same file) supplies `body`.
    // Detection is file-scope per type, not per member block.
    let source = """
      extension MyParser: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
      }
      extension MyParser {
          public var body: some Parser.`Protocol` {
              Binary.LEB128.Unsigned<Int>()
          }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func `conformance and Body Never typealias split across two extensions is NOT flagged`() {
    let source = """
      extension MyParser: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      extension MyParser {
          public typealias Body = Never
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }

  @Test
  func
    `conformance in one extension, body missing everywhere for that type, is still flagged once`()
  {
    let source = """
      extension MyParser: Parser.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public typealias Failure = Never
          public func parse(_ input: inout Input) throws(Failure) -> Int { 0 }
      }
      extension MyParser {
          public func helper() -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.count == 1)
  }

  @Test
  func `same-named Protocol on a different host namespace is NOT flagged`() {
    // Detection is gated on the host pair (Parser/Serializer/Coder).
    // `Other.Protocol` is structurally similar but out of scope.
    let source = """
      extension X: Other.`Protocol` {
          public typealias Input = [UInt8]
          public typealias Output = Int
          public func compute() -> Int { 0 }
      }
      """
    let findings = Lint.Rule.`leaf body typealias missing Tests`.findings(in: source)
    #expect(findings.isEmpty)
  }
}
