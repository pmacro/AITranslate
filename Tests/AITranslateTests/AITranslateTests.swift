import Testing
import Foundation
@testable import AITranslate
@testable import AITranslateLib

struct AITranslateCommandTests {
  @Test func parsesArguments() throws {
    let command = try AITranslateCommand.parseAsRoot([
      "/path/to/Localizable.xcstrings",
      "-o", "test-api-key",
      "-v",
      "-l", "de,es,fr"
    ])

    let parsed = try #require(command as? AITranslateCommand)
    #expect(parsed.verbose == true)
    #expect(parsed.skipBackup == false)
    #expect(parsed.force == false)
    #expect(parsed.languages == ["de", "es", "fr"])
    #expect(parsed.openAIKey == "test-api-key")
  }

  @Test func parsesNoTuiFlag() throws {
    let command = try AITranslateCommand.parseAsRoot([
      "/path/to/Localizable.xcstrings",
      "-o", "test-api-key",
      "-l", "de",
      "--no-tui"
    ])

    let parsed = try #require(command as? AITranslateCommand)
    #expect(parsed.noTui == true)
  }

  @Test func mockAPIUsedInTestEnvironment() {
    let translate = AITranslateLib.AITranslate(
      inputFile: URL(fileURLWithPath: "/tmp/test.xcstrings"),
      languages: ["de"],
      openAIKey: "test",
      verbose: false,
      skipBackup: true,
      force: false
    )
    #expect(translate.api is MockAPI)
  }
}
