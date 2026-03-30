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

  static let batchSystemPrompt =
    """
    You are a translator tool that translates UI strings for a software application.
    You will receive a JSON array of entries to translate. Each entry has an "id" (integer),
    "text" (the string to translate), and optionally "context" (describing how the text is used).

    Rules:
    - Translate each entry's "text" from the source language to the target language.
    - Include *only* the translation for each entry — no metadata, tags, periods, quotes, or new lines unless present in the original.
    - Placeholders (like %@, %d, %1$@, etc) must be preserved exactly as they appear.
    - Multi-letter abbreviations (HTML, URL, API, HTTP, HTTPS, JSON, XML, CPU, GPU, RAM, ID, UI, UX, etc) are case-sensitive and must not be translated.

    Return a JSON object with a "translations" array containing the translated strings in the same order as the input entries.
    """

  static let batchSize = 20

  let inputFile: URL
  let languages: [String]
  let openAIKey: String
  let verbose: Bool
  let skipBackup: Bool
  let force: Bool
  let matchXcodeOrdering: Bool
  let reporter: ProgressReporter

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
    force: Bool,
    matchXcodeOrdering: Bool = false,
    reporter: ProgressReporter? = nil
  ) {
    self.inputFile = inputFile
    self.languages = languages
    self.openAIKey = openAIKey
    self.verbose = verbose
    self.skipBackup = skipBackup
    self.force = force
    self.matchXcodeOrdering = matchXcodeOrdering
    self.reporter = reporter ?? SimpleProgressReporter()
  }

  public func run() async throws {
    do {
      let catalog = try JSONDecoder().decode(
        StringCatalog.self,
        from: try Data(contentsOf: inputFile)
      )

      // Force lazy initialization before concurrent access.
      _ = self.api

      // Collect all work items, handling untranslatable entries immediately.
      var workItems: [WorkItem] = []

      for (key, group) in catalog.strings {
        let localizationEntries = group.localizations ?? [:]

        for lang in languages {
          let unit = localizationEntries[lang]

          if let unit, unit.hasTranslation, force == false {
            continue
          }

          if let unit, unit.isSupportedFormat == false {
            await reporter.warning("Unsupported format in entry with key: \(key)")
            continue
          }

          let sourceText = localizationEntries[catalog.sourceLanguage]?.stringUnit?.value ?? key

          // Handle text that doesn't need API translation.
          if isUntranslatable(sourceText) {
            if group.localizations == nil { group.localizations = [:] }
            group.localizations?[lang] = LocalizationUnit(
              stringUnit: StringUnit(state: "translated", value: sourceText)
            )
            continue
          }

          workItems.append(WorkItem(
            key: key,
            sourceText: sourceText,
            context: group.comment,
            localizationGroup: group,
            language: lang
          ))
        }
      }

      let byLanguage = Dictionary(grouping: workItems, by: \.language)
      let perLanguageCounts = byLanguage.mapValues { $0.count }
      let activeLanguages = languages.filter { byLanguage[$0] != nil }

      await reporter.translationStarted(
        totalEntries: workItems.count,
        languages: activeLanguages,
        perLanguageCounts: perLanguageCounts
      )

      // Chunk each language's items into batches, then interleave across languages
      // so the overall progress bar advances evenly.
      var perLanguageBatches: [[(language: String, items: [WorkItem])]] = []
      for lang in activeLanguages {
        guard let items = byLanguage[lang] else { continue }
        perLanguageBatches.append(items.chunked(into: Self.batchSize).map { (lang, $0) })
      }

      var allBatches: [(language: String, items: [WorkItem])] = []
      var index = 0
      while allBatches.count < perLanguageBatches.reduce(0, { $0 + $1.count }) {
        for langBatches in perLanguageBatches {
          if index < langBatches.count {
            allBatches.append(langBatches[index])
          }
        }
        index += 1
      }

      // Process batches concurrently, apply results serially.
      let maxConcurrent = 5

      try await withThrowingTaskGroup(
        of: [(item: WorkItem, translation: String?)].self
      ) { group in
        var inFlight = 0

        for batch in allBatches {
          if inFlight >= maxConcurrent {
            if let results = try await group.next() {
              await applyResults(results)
            }
            inFlight -= 1
          }

          let items = batch.items
          let lang = batch.language
          group.addTask {
            let inputs = items.map { (sourceText: $0.sourceText, context: $0.context) }
            let translations = try await self.performBatchTranslation(
              entries: inputs,
              from: catalog.sourceLanguage,
              to: lang,
              api: self.api
            )
            return zip(items, translations).map { (item: $0.0, translation: $0.1) }
          }
          inFlight += 1
        }

        while let results = try await group.next() {
          await applyResults(results)
        }
      }

      try save(catalog)
      await reporter.finished()
    } catch let error {
      await reporter.finished()
      throw error
    }
  }

  private func applyResults(_ results: [(item: WorkItem, translation: String?)]) async {
    for (item, translation) in results {
      if item.localizationGroup.localizations == nil {
        item.localizationGroup.localizations = [:]
      }
      item.localizationGroup.localizations?[item.language] = LocalizationUnit(
        stringUnit: StringUnit(
          state: translation != nil ? "translated" : "error",
          value: translation ?? ""
        )
      )

      if verbose, let translation {
        await reporter.verboseLog("[\(item.language)] " + item.sourceText + " -> " + translation)
      }

      await reporter.translationCompleted(
        key: item.key,
        language: item.language,
        success: translation != nil
      )
    }
  }

  func isUntranslatable(_ text: String) -> Bool {
    text.isEmpty ||
      text.trimmingCharacters(
        in: .whitespacesAndNewlines
          .union(.symbols)
          .union(.controlCharacters)
      ).isEmpty
  }

  // MARK: - Batch Translation

  func performBatchTranslation(
    entries: [(sourceText: String, context: String?)],
    from source: String,
    to target: String,
    api: API
  ) async throws -> [String?] {
    let batchEntries = entries.enumerated().map { (i, entry) in
      TranslationBatchEntry(id: i, text: entry.sourceText, context: entry.context)
    }

    let entriesJSON = try String(
      data: JSONEncoder().encode(batchEntries),
      encoding: .utf8
    )!

    let userMessage = "<source>\(source)</source><target>\(target)</target><entries>\(entriesJSON)</entries>"

    let query = ChatQuery(
      messages: [
        .init(role: .system, content: Self.batchSystemPrompt)!,
        .init(role: .user, content: userMessage)!
      ],
      model: .gpt5_mini,
      responseFormat: .jsonSchema(
        .init(
          name: "batch-translations",
          schema: .derivedJsonSchema(BatchTranslationResponse.self),
          strict: true
        )
      )
    )

    do {
      let result = try await api.chats(query: query)
      let content = result.choices.first?.message.content ?? ""

      guard let data = content.data(using: .utf8),
            let response = try? JSONDecoder().decode(BatchTranslationResponse.self, from: data),
            response.translations.count == entries.count else {
        // Count mismatch or parse failure: fall back to individual calls.
        await reporter.warning("Batch response mismatch for \(target), falling back to individual translations")
        return try await fallbackToIndividual(entries: entries, from: source, to: target, api: api)
      }

      return response.translations.map { $0 as String? }
    } catch {
      // Batch call failed entirely: fall back to individual calls.
      await reporter.warning("Batch call failed for \(target), falling back to individual translations")
      return try await fallbackToIndividual(entries: entries, from: source, to: target, api: api)
    }
  }

  private func fallbackToIndividual(
    entries: [(sourceText: String, context: String?)],
    from source: String,
    to target: String,
    api: API
  ) async throws -> [String?] {
    var results: [String?] = []
    for entry in entries {
      let result = try await performTranslation(
        entry.sourceText,
        from: source,
        to: target,
        context: entry.context,
        api: api
      )
      results.append(result)
    }
    return results
  }

  // MARK: - Single Translation (used by fallback and tests)

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
        await reporter.warning("Unsupported format in entry with key: \(key)")
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

      let success = result != nil
      await reporter.translationCompleted(key: key, language: lang, success: success)
    }
  }

  func save(_ catalog: StringCatalog) throws {
    let data: Data

    if matchXcodeOrdering {
      let encoded = try JSONEncoder().encode(catalog)
      let jsonObject = try JSONSerialization.jsonObject(with: encoded)
      data = try JSONSerialization.data(
        withJSONObject: jsonObject,
        options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
      )
    } else {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
      data = try encoder.encode(catalog)
    }

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
    if isUntranslatable(text) {
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
        await reporter.verboseLog("[\(target)] " + text + " -> " + translation)
      }

      return translation
    } catch let error {
      await reporter.error("Failed to translate \(text) into \(target)")

      if verbose {
        await reporter.verboseLog("[💥] " + error.localizedDescription)
      }

      return nil
    }
  }
}

// MARK: - Batch Types

struct TranslationBatchEntry: Codable {
  let id: Int
  let text: String
  let context: String?
}

struct BatchTranslationResponse: JSONSchemaConvertible {
  let translations: [String]

  static var example: BatchTranslationResponse {
    BatchTranslationResponse(translations: ["Hallo", "Speichern", "Abbrechen"])
  }
}

struct WorkItem {
  let key: String
  let sourceText: String
  let context: String?
  let localizationGroup: LocalizationGroup
  let language: String
}

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
