import Testing
import Foundation
@testable import AITranslateLib

struct StringCatalogTests {
  private func loadXCStrings(named name: String) throws -> StringCatalog {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: "xcstrings", subdirectory: "Fixtures")
    )
    return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
  }

  // MARK: - Parsing

  @Test func simpleParsing() throws {
    let content = try loadXCStrings(named: "Simple")

    #expect(content.sourceLanguage == "en")
    #expect(content.strings.count == 1)

    let entry = try #require(content.strings.first)
    #expect(entry.key == "My Key")
    #expect(entry.value.comment == "My Comment")
    #expect(entry.value.localizations?.keys.sorted() == ["en"])
  }

  @Test func variationParsing() throws {
    let content = try loadXCStrings(named: "WithVariations")

    #expect(content.sourceLanguage == "en")
    #expect(content.strings.count == 1)

    let entry = try #require(content.strings.first)
    #expect(entry.key == "My Key")

    let unit = try #require(entry.value.localizations?["en"])
    #expect(unit.substitutions == nil)
    #expect(unit.variations?.plural == nil)

    let deviceVariations = try #require(unit.variations?.device)
    #expect(deviceVariations.mac?.stringUnit.value == "Click")
    #expect(deviceVariations.other?.stringUnit.value == "Tap")
    #expect(deviceVariations.applevision?.stringUnit.value == "Look")
  }

  @Test func pluralParsing() throws {
    let content = try loadXCStrings(named: "WithPlurals")

    #expect(content.sourceLanguage == "en")
    #expect(content.strings.count == 1)

    let entry = try #require(content.strings.first)
    #expect(entry.key == "My Key")

    let unit = try #require(entry.value.localizations?["en"])
    #expect(unit.substitutions == nil)
    #expect(unit.variations?.device == nil)

    let pluralVariations = try #require(unit.variations?.plural)
    #expect(pluralVariations.zero?.stringUnit.value == "Zero")
    #expect(pluralVariations.one?.stringUnit.value == "%d One")
    #expect(pluralVariations.other?.stringUnit.value == "%d Other")
  }

  // MARK: - Computed properties

  @Test func isSupportedFormatWithPlainStringUnit() {
    let unit = LocalizationUnit(stringUnit: StringUnit(state: "translated", value: "Hello"))
    #expect(unit.isSupportedFormat == true)
  }

  @Test func isSupportedFormatFalseWithVariations() {
    let unit = LocalizationUnit(stringUnit: nil, variations: VariationsUnit())
    #expect(unit.isSupportedFormat == false)
  }

  @Test func isSupportedFormatFalseWithSubstitutions() {
    let unit = LocalizationUnit(
      stringUnit: nil,
      substitutions: ["arg": SubstitutionsUnit(formatSpecifier: "%d", variations: VariationsUnit())]
    )
    #expect(unit.isSupportedFormat == false)
  }

  @Test func hasTranslationWithValue() {
    let unit = LocalizationUnit(stringUnit: StringUnit(state: "translated", value: "Hello"))
    #expect(unit.hasTranslation == true)
  }

  @Test func hasTranslationFalseWithEmptyValue() {
    let unit = LocalizationUnit(stringUnit: StringUnit(state: "translated", value: ""))
    #expect(unit.hasTranslation == false)
  }

  @Test func hasTranslationFalseWithNilStringUnit() {
    let unit = LocalizationUnit(stringUnit: nil)
    #expect(unit.hasTranslation == false)
  }

  // MARK: - Round-trip encoding

  @Test func roundTripEncoding() throws {
    let catalog = try loadXCStrings(named: "Simple")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let encoded = try encoder.encode(catalog)
    let decoded = try JSONDecoder().decode(StringCatalog.self, from: encoded)

    #expect(decoded.sourceLanguage == catalog.sourceLanguage)
    #expect(decoded.version == catalog.version)
    #expect(decoded.strings.count == catalog.strings.count)

    let originalEntry = try #require(catalog.strings["My Key"])
    let decodedEntry = try #require(decoded.strings["My Key"])
    #expect(decodedEntry.comment == originalEntry.comment)
    #expect(decodedEntry.localizations?["en"]?.stringUnit?.value == originalEntry.localizations?["en"]?.stringUnit?.value)
  }
}
