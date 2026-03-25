//
//  AITranslate.swift
//
//
//  Created by Paul MacRory on 3/7/24.
//

import ArgumentParser
import OpenAI
import Foundation
import AITranslateLib

@main
struct AITranslateCommand: AsyncParsableCommand {
  static func gatherLanguages(from input: String) -> [String] {
    input.split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespaces) }
  }

  @Argument(transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("A comma separated list of language codes (must match the language codes used by xcstrings)"), 
    transform: AITranslateCommand.gatherLanguages(from:)
  )
  var languages: [String]

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("Your OpenAI API key, see: https://platform.openai.com/api-keys")
  )
  var openAIKey: String

  @Flag(name: .shortAndLong)
  var verbose: Bool = false

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp("By default a backup of the input will be created. When this flag is provided, the backup is skipped.")
  )
  var skipBackup: Bool = false

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp("Forces all strings to be translated, even if an existing translation is present.")
  )
  var force: Bool = false

  mutating func run() async throws {
    try await AITranslate(
      inputFile: inputFile,
      languages: languages,
      openAIKey: openAIKey,
      verbose: verbose,
      skipBackup: skipBackup,
      force: force
    ).run()
  }
}
