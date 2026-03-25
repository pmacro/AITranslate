//
//  AITranslate.swift
//
//
//  Created by Paul MacRory on 3/7/24.
//

import ArgumentParser
import OpenAI
import Foundation

public final class AITranslate: @unchecked Sendable {
  static let systemPrompt =
    """
    You are a translator tool that translates UI strings for a software application.
    Your inputs will be a source language, a target language, the original text, and
    optionally some context to help you understand how the original text is used within
    the application. Each piece of information will be inside some XML-like tags.
    In your response include *only* the translation, and do not include any metadata, tags,
    periods, quotes, or new lines, unless included in the original text.
    Placeholders (like %@, %d, %1$@, etc) should be preserved exactly as they appear in the original text.
    Treat multi-letter abbreviations (such as common technical acronyms like "HTML", "URL", "API", "HTTP", "HTTPS", "JSON", "XML", "CPU", "GPU", "RAM", "ID", "UI", "UX", etc) as case-sensitive and do not translate them.
    """

  let inputFile: URL
  let languages: [String]
  let openAIKey: String
  let verbose: Bool
  let skipBackup: Bool
  let force: Bool

  lazy var api: API = {
    let configuration = OpenAI.Configuration(
      token: openAIKey,
      organizationIdentifier: nil,
      timeoutInterval: 60.0
    )

    return APIRegistry.current.create(with: configuration)
  }()

  public init(
    inputFile: URL,
    languages: [String],
    openAIKey: String,
    verbose: Bool,
    skipBackup: Bool,
    force: Bool
  ) {
    self.inputFile = inputFile
    self.languages = languages
    self.openAIKey = openAIKey
    self.verbose = verbose
    self.skipBackup = skipBackup
    self.force = force
  }

  public func run() async throws {
    do {
      let catalog = try JSONDecoder().decode(
        StringCatalog.self,
        from: try Data(contentsOf: inputFile)
      )

      let totalEntries = catalog.strings.count
      let start = Date()
      var previousPercentage: Int = -1
      var entriesCompleted = 0

      // Force lazy initialization before concurrent access.
      _ = self.api

      let maxConcurrent = 5

      try await withThrowingTaskGroup(of: Void.self) { group in
        var inFlight = 0

        for entry in catalog.strings {
          if inFlight >= maxConcurrent {
            try await group.next()
            inFlight -= 1
            entriesCompleted += 1

            let percentageProcessed = Int(Double(entriesCompleted) / Double(totalEntries) * 100)
            if percentageProcessed != previousPercentage, percentageProcessed % 10 == 0 {
              print("[⏳] \(percentageProcessed)%")
              previousPercentage = percentageProcessed
            }
          }

          group.addTask {
            try await self.processEntry(
              key: entry.key,
              localizationGroup: entry.value,
              sourceLanguage: catalog.sourceLanguage
            )
          }
          inFlight += 1
        }

        while let _ = try await group.next() {
          entriesCompleted += 1
          let percentageProcessed = Int(Double(entriesCompleted) / Double(totalEntries) * 100)
          if percentageProcessed != previousPercentage, percentageProcessed % 10 == 0 {
            print("[⏳] \(percentageProcessed)%")
            previousPercentage = percentageProcessed
          }
        }
      }

      try save(catalog)

      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = [.hour, .minute, .second]
      formatter.unitsStyle = .full
      let formattedString = formatter.string(from: Date().timeIntervalSince(start))!

      print("[✅] 100% \n[⏰] Translations time: \(formattedString)")
    } catch let error {
      throw error
    }
  }

  func processEntry(
    key: String,
    localizationGroup: LocalizationGroup,
    sourceLanguage: String
  ) async throws {
    for lang in languages {
      let localizationEntries = localizationGroup.localizations ?? [:]
      let unit = localizationEntries[lang]

      // Nothing to do.
      if let unit, unit.hasTranslation, force == false {
        continue
      }

      // Skip the ones with variations/substitutions since they are not supported.
      if let unit, unit.isSupportedFormat == false {
        print("[⚠️] Unsupported format in entry with key: \(key)")
        continue
      }

      // The source text can either be the key or an explicit value in the `localizations`
      // dictionary keyed by `sourceLanguage`.
      let sourceText = localizationEntries[sourceLanguage]?.stringUnit?.value ?? key

      let result = try await performTranslation(
        sourceText,
        from: sourceLanguage,
        to: lang,
        context: localizationGroup.comment,
        api: api
      )

      localizationGroup.localizations = localizationEntries
      localizationGroup.localizations?[lang] = LocalizationUnit(
        stringUnit: StringUnit(
          state: result == nil ? "error" : "translated",
          value: result ?? ""
        )
      )
    }
  }

  func save(_ catalog: StringCatalog) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    let data = try encoder.encode(catalog)

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
    api: API
  ) async throws -> String? {

    // Skip text that is generally not translated.
    if text.isEmpty ||
        text.trimmingCharacters(
          in: .whitespacesAndNewlines
            .union(.symbols)
            .union(.controlCharacters)
        ).isEmpty {
      return text
    }

    var translationRequest = "<source>\(source)</source>"
    translationRequest += "<target>\(target)</target>"
    translationRequest += "<original>\(text)</original>"

    if let context {
      translationRequest += "<context>\(context)</context>"
    }

    let query = ChatQuery(
      messages: [
        .init(role: .system, content: Self.systemPrompt)!,
        .init(role: .user, content: translationRequest)!
      ],
      model: .gpt5_mini
    )

    do {
      let result = try await api.chats(query: query)
      let translation = result.choices.first?.message.content ?? text

      if verbose {
        print("[\(target)] " + text + " -> " + translation)
      }

      return translation
    } catch let error {
      print("[❌] Failed to translate \(text) into \(target)")

      if verbose {
        print("[💥]" + error.localizedDescription)
      }

      return nil
    }
  }
}
