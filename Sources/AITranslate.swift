// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import OpenAI
import Foundation

@main
struct AITranslate: AsyncParsableCommand {
  @Argument(transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  @Option(
    name: .shortAndLong,
    transform: AITranslate.gatherLanguages(from:)
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

  static func gatherLanguages(from input: String) -> [String] {
    input.split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespaces) }
  }

  mutating func run() async throws {
    let configuration = OpenAI.Configuration(
      token: openAIKey,
      organizationIdentifier: nil,
      timeoutInterval: 60.0
    )

    let openAI = OpenAI(configuration: configuration)

    do {
      let dict = try JSONDecoder().decode(
        StringsDict.self,
        from: try Data(contentsOf: inputFile)
      )

      let total = Double(dict.strings.count * languages.count)
      var count: Double = 0
      let start = Date()
      var previousPercentage: Int = -1

      for entry in dict.strings {
        let percentage = Int((count / total) * 100)

        if percentage != previousPercentage, percentage % 10 == 0 {
          print("\(percentage)%")
          previousPercentage = percentage
        }

        for lang in languages {
          count += 1
          let localizations = entry.value.localizations ?? [:]

          guard force || localizations[lang] == nil else {
            continue
          }

          // The source text can either be the key or an explicit value in the `localizations`
          // dictionary keyed by `sourceLanguage`.
          let sourceText = localizations[dict.sourceLanguage]?.stringUnit.value ?? entry.key

          let result = try await performTranslation(
            sourceText,
            from: dict.sourceLanguage,
            to: lang,
            context: entry.value.comment,
            openAI: openAI
          )

          entry.value.localizations = localizations
          entry.value.localizations?[lang] = LocalizationUnit(
            stringUnit: StringUnit(
              state: result == nil ? "error" : "translated",
              value: result ?? ""
            )
          )
        }
      }

      try save(dict)

      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = [.hour, .minute, .second]
      formatter.unitsStyle = .full
      let formattedString = formatter.string(from: Date().timeIntervalSince(start))!

      print("100% ✅\nTranslations time: \(formattedString) 🕝")
    } catch let error {
      throw error
    }
  }

  func save(_ dict: StringsDict) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(dict)

    try backupInputFileIfNecessary()
    try data.write(to: inputFile)
  }

  func backupInputFileIfNecessary() throws {
    if skipBackup == false {
      let backupFileURL = inputFile.appendingPathExtension("original")

      try? FileManager.default.trashItem(
        at: backupFileURL,
        resultingItemURL: nil
      )

      try FileManager.default.moveItem(
        at: inputFile,
        to: backupFileURL
      )
    }
  }

  func performTranslation(
    _ text: String,
    from source: String,
    to target: String,
    context: String? = nil,
    openAI: OpenAI
  ) async throws -> String? {

    // Skip that is generally not translated.
    if text.isEmpty ||
        text.trimmingCharacters(
          in: .whitespacesAndNewlines
            .union(.symbols)
            .union(.controlCharacters)
        ).isEmpty {
      return text
    }

    let prompt = "You are a translator tool that translates UI strings for a software application. Your inputs will be a source language, a target language, the original text, and optionally some context to help you understand the context of the original text within the application. Each piece of information will be inside some XML-like tags, to help you understand the information. In your response include *only* the translation, and do not include any metadata, tags, periods, quotes, new lines, or speechmarks unless included in the original text."

    var translationRequest = "<source>\(source)</source><target>\(target)</target>"
    translationRequest += "<original>\(text)</original>"

    if let context {
      translationRequest += "<context>\(context)</context>"
    }

    let query = ChatQuery(
      messages: [
        .init(role: .system, content: prompt)!,
        .init(role: .user, content: translationRequest)!
      ],
      model: .gpt4_turbo_preview
    )

    guard let result = try? await openAI.chats(query: query) else {
      print("Error: Failed to translate \(text)")
      return nil
    }

    let translation = result.choices.first?.message.content?.string ?? text
    
    if verbose {
      print("[\(target)] " + text + " -> " + translation)
    }

    return translation
  }
}
