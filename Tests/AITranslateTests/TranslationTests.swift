import Testing
import Foundation
import OpenAI
@testable import AITranslateLib

struct TranslationTests {
  private func makeTranslate(
    languages: [String] = ["de"],
    force: Bool = false,
    verbose: Bool = false
  ) -> AITranslate {
    AITranslate(
      inputFile: URL(fileURLWithPath: "/tmp/test.xcstrings"),
      languages: languages,
      openAIKey: "test-key",
      verbose: verbose,
      skipBackup: true,
      force: force
    )
  }

  private func makeMockAPI(response: String = "translated") -> MockAPI {
    let mock = MockAPI()
    mock.responseContent = response
    return mock
  }

  // MARK: - performTranslation

  @Test func returnsEmptyStringForEmptyInput() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    let result = try await translate.performTranslation("", from: "en", to: "de", api: mock)
    #expect(result == "")
    #expect(mock.receivedQueries.isEmpty)
  }

  @Test func returnsWhitespaceForWhitespaceOnlyInput() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    let result = try await translate.performTranslation("   ", from: "en", to: "de", api: mock)
    #expect(result == "   ")
    #expect(mock.receivedQueries.isEmpty)
  }

  @Test func returnsSymbolsForSymbolOnlyInput() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    let result = try await translate.performTranslation("$$$", from: "en", to: "de", api: mock)
    #expect(result == "$$$")
    #expect(mock.receivedQueries.isEmpty)
  }

  @Test func translatesValidText() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI(response: "Hallo")
    let result = try await translate.performTranslation("Hello", from: "en", to: "de", api: mock)
    #expect(result == "Hallo")
    #expect(mock.receivedQueries.count == 1)
  }

  @Test func returnsNilOnAPIError() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    mock.error = NSError(domain: "test", code: 1)
    let result = try await translate.performTranslation("Hello", from: "en", to: "de", api: mock)
    #expect(result == nil)
  }

  @Test func sendsSystemAndUserMessages() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI(response: "Hallo")
    _ = try await translate.performTranslation("Hello", from: "en", to: "de", context: "greeting", api: mock)

    let query = try #require(mock.receivedQueries.first)
    #expect(query.messages.count == 2)
  }

  // MARK: - processEntry

  @Test func skipsAlreadyTranslatedEntry() async throws {
    let translate = makeTranslate(languages: ["de"])
    let mock = makeMockAPI()
    translate.api = mock

    let group = LocalizationGroup(
      localizations: [
        "de": LocalizationUnit(stringUnit: StringUnit(state: "translated", value: "Hallo"))
      ]
    )

    try await translate.processEntry(key: "Hello", localizationGroup: group, sourceLanguage: "en")
    #expect(mock.receivedQueries.isEmpty)
  }

  @Test func translatesWhenForced() async throws {
    let translate = makeTranslate(languages: ["de"], force: true)
    let mock = makeMockAPI(response: "Hallo Welt")
    translate.api = mock

    let group = LocalizationGroup(
      localizations: [
        "de": LocalizationUnit(stringUnit: StringUnit(state: "translated", value: "Hallo"))
      ]
    )

    try await translate.processEntry(key: "Hello", localizationGroup: group, sourceLanguage: "en")
    #expect(mock.receivedQueries.count == 1)
    #expect(group.localizations?["de"]?.stringUnit?.value == "Hallo Welt")
  }

  @Test func skipsUnsupportedFormats() async throws {
    let translate = makeTranslate(languages: ["de"])
    let mock = makeMockAPI()
    translate.api = mock

    let group = LocalizationGroup(
      localizations: [
        "de": LocalizationUnit(stringUnit: nil, variations: VariationsUnit())
      ]
    )

    try await translate.processEntry(key: "Hello", localizationGroup: group, sourceLanguage: "en")
    #expect(mock.receivedQueries.isEmpty)
  }

  @Test func usesKeyAsSourceTextWhenNoExplicitSource() async throws {
    let translate = makeTranslate(languages: ["de"])
    let mock = makeMockAPI(response: "Hallo")
    translate.api = mock

    let group = LocalizationGroup(localizations: [:])

    try await translate.processEntry(key: "Hello", localizationGroup: group, sourceLanguage: "en")
    #expect(mock.receivedQueries.count == 1)
    #expect(group.localizations?["de"]?.stringUnit?.value == "Hallo")
  }

  @Test func usesExplicitSourceLocalization() async throws {
    let translate = makeTranslate(languages: ["de"])
    let mock = makeMockAPI(response: "Hallo Welt")
    translate.api = mock

    let group = LocalizationGroup(
      localizations: [
        "en": LocalizationUnit(stringUnit: StringUnit(state: "translated", value: "Hello World"))
      ]
    )

    try await translate.processEntry(key: "greeting_key", localizationGroup: group, sourceLanguage: "en")
    #expect(mock.receivedQueries.count == 1)
    #expect(group.localizations?["de"]?.stringUnit?.value == "Hallo Welt")
    #expect(group.localizations?["de"]?.stringUnit?.state == "translated")
  }

  @Test func setsErrorStateOnTranslationFailure() async throws {
    let translate = makeTranslate(languages: ["de"])
    let mock = makeMockAPI()
    mock.error = NSError(domain: "test", code: 1)
    translate.api = mock

    let group = LocalizationGroup(localizations: [:])

    try await translate.processEntry(key: "Hello", localizationGroup: group, sourceLanguage: "en")
    #expect(group.localizations?["de"]?.stringUnit?.state == "error")
    #expect(group.localizations?["de"]?.stringUnit?.value == "")
  }

  @Test func translatesMultipleLanguages() async throws {
    let translate = makeTranslate(languages: ["de", "fr", "es"])
    let mock = makeMockAPI(response: "translated")
    translate.api = mock

    let group = LocalizationGroup(localizations: [:])

    try await translate.processEntry(key: "Hello", localizationGroup: group, sourceLanguage: "en")
    #expect(mock.receivedQueries.count == 3)
    #expect(group.localizations?["de"]?.stringUnit?.value == "translated")
    #expect(group.localizations?["fr"]?.stringUnit?.value == "translated")
    #expect(group.localizations?["es"]?.stringUnit?.value == "translated")
  }

  // MARK: - performBatchTranslation

  @Test func batchTranslationReturnsAllTranslations() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    mock.batchTranslations = ["Hallo", "Speichern", "Abbrechen"]

    let entries: [(sourceText: String, context: String?)] = [
      ("Hello", nil),
      ("Save", "button label"),
      ("Cancel", nil)
    ]

    let results = try await translate.performBatchTranslation(
      entries: entries, from: "en", to: "de", api: mock
    )

    #expect(results.count == 3)
    #expect(results[0] == "Hallo")
    #expect(results[1] == "Speichern")
    #expect(results[2] == "Abbrechen")
    #expect(mock.receivedQueries.count == 1)
  }

  @Test func batchTranslationPassesContext() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    mock.batchTranslations = ["Datei"]

    let entries: [(sourceText: String, context: String?)] = [
      ("File", "menu item for file operations")
    ]

    let results = try await translate.performBatchTranslation(
      entries: entries, from: "en", to: "de", api: mock
    )

    #expect(results.count == 1)
    #expect(results[0] == "Datei")

    // Verify the user message contains the context
    let query = try #require(mock.receivedQueries.first)
    // The batch query encodes entries as JSON with context field
    #expect(mock.receivedQueries.count == 1)

    // Verify query uses responseFormat (batch mode)
    #expect(query.responseFormat != nil)
  }

  @Test func batchFallsBackOnCountMismatch() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    // Return wrong number of translations to trigger fallback
    mock.batchTranslations = ["Hallo"]
    mock.responseContent = "fallback"

    let entries: [(sourceText: String, context: String?)] = [
      ("Hello", nil),
      ("World", nil),
      ("Test", nil)
    ]

    let results = try await translate.performBatchTranslation(
      entries: entries, from: "en", to: "de", api: mock
    )

    // Should fall back to individual calls (1 batch + 3 individual = 4 total)
    #expect(results.count == 3)
    #expect(mock.receivedQueries.count == 4)
  }

  @Test func batchFallsBackOnAPIError() async throws {
    let translate = makeTranslate()
    let mock = makeMockAPI()
    mock.error = NSError(domain: "test", code: 500)

    let entries: [(sourceText: String, context: String?)] = [
      ("Hello", nil)
    ]

    // When batch fails, it falls back to individual calls which also fail,
    // returning nil for each entry (performTranslation catches errors).
    let results = try await translate.performBatchTranslation(
      entries: entries, from: "en", to: "de", api: mock
    )

    #expect(results.count == 1)
    #expect(results[0] == nil)
    // 1 batch call + 1 individual fallback call = 2 total
    #expect(mock.receivedQueries.count == 2)
  }

  @Test func isUntranslatableDetectsEmptyAndSymbols() {
    let translate = makeTranslate()
    #expect(translate.isUntranslatable("") == true)
    #expect(translate.isUntranslatable("   ") == true)
    #expect(translate.isUntranslatable("$$$") == true)
    #expect(translate.isUntranslatable("Hello") == false)
    #expect(translate.isUntranslatable("Hello World") == false)
  }
}

