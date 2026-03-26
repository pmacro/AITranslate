import Testing
import Foundation
@testable import AITranslateLib

struct TranslationProgressTests {
  @Test func initialSnapshotIsZero() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 10, languages: ["de", "fr"])
    let snap = await progress.snapshot()

    #expect(snap.totalEntries == 10)
    #expect(snap.totalCompleted == 0)
    #expect(snap.totalFailed == 0)
    #expect(snap.percentage == 0)
    #expect(snap.isFinished == false)
    #expect(snap.languages.count == 2)
    #expect(snap.languages[0].language == "de")
    #expect(snap.languages[1].language == "fr")
  }

  @Test func recordCompletionUpdatesState() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 2, languages: ["de"])

    await progress.recordCompletion(key: "hello", language: "de", success: true)
    let snap = await progress.snapshot()

    #expect(snap.totalCompleted == 1)
    #expect(snap.totalFailed == 0)
    #expect(snap.languages[0].completed == 1)
    #expect(snap.languages[0].status == .active)
  }

  @Test func recordFailureUpdatesState() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 2, languages: ["de"])

    await progress.recordCompletion(key: "hello", language: "de", success: false)
    let snap = await progress.snapshot()

    #expect(snap.totalCompleted == 1)
    #expect(snap.totalFailed == 1)
    #expect(snap.languages[0].failed == 1)
  }

  @Test func languageBecomeDoneWhenAllCompleted() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 2, languages: ["de"])

    await progress.recordCompletion(key: "a", language: "de", success: true)
    await progress.recordCompletion(key: "b", language: "de", success: true)
    let snap = await progress.snapshot()

    #expect(snap.languages[0].status == .done)
    #expect(snap.percentage == 100)
  }

  @Test func markFinishedSetsAllDone() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 5, languages: ["de", "fr"])

    await progress.markFinished()
    let snap = await progress.snapshot()

    #expect(snap.isFinished == true)
    for lang in snap.languages {
      #expect(lang.status == .done)
    }
  }

  @Test func warningAndErrorCounts() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 5, languages: ["de"])

    await progress.recordWarning()
    await progress.recordWarning()
    await progress.recordError()
    let snap = await progress.snapshot()

    #expect(snap.warningCount == 2)
    #expect(snap.errorCount == 1)
  }

  @Test func percentageClampedTo100() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 1, languages: ["de"])

    // Complete more than total (edge case)
    await progress.recordCompletion(key: "a", language: "de", success: true)
    await progress.recordCompletion(key: "b", language: "de", success: true)
    let snap = await progress.snapshot()

    #expect(snap.percentage <= 100)
  }

  @Test func multipleLanguagesTrackedIndependently() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 3, languages: ["de", "fr", "es"])

    await progress.recordCompletion(key: "a", language: "de", success: true)
    await progress.recordCompletion(key: "a", language: "fr", success: false)
    let snap = await progress.snapshot()

    #expect(snap.languages[0].completed == 1) // de
    #expect(snap.languages[0].failed == 0)
    #expect(snap.languages[1].completed == 1) // fr
    #expect(snap.languages[1].failed == 1)
    #expect(snap.languages[2].completed == 0) // es
    #expect(snap.totalCompleted == 2)
    #expect(snap.totalFailed == 1)
  }
}
