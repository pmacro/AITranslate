import Testing
import Foundation
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
}
