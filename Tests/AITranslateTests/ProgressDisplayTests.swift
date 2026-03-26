import Testing
import Foundation
@testable import AITranslateLib

struct ProgressDisplayTests {
  @Test func renderProducesOutput() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 10, languages: ["de", "fr"])
    let display = ProgressDisplay(progress: progress)

    // Just verify render doesn't crash with a fresh snapshot
    let snap = await progress.snapshot()
    display.render(snap)
  }

  @Test func renderAfterCompletions() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 4, languages: ["de", "fr"])

    await progress.recordCompletion(key: "a", language: "de", success: true)
    await progress.recordCompletion(key: "a", language: "fr", success: true)
    await progress.recordCompletion(key: "b", language: "de", success: false)

    let display = ProgressDisplay(progress: progress)
    let snap = await progress.snapshot()
    display.render(snap)
  }

  @Test func renderFinishedState() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 2, languages: ["de"])

    await progress.recordCompletion(key: "a", language: "de", success: true)
    await progress.recordCompletion(key: "b", language: "de", success: true)
    await progress.markFinished()

    let display = ProgressDisplay(progress: progress)
    let snap = await progress.snapshot()
    display.render(snap)
    // If we reach here without crash, the render works for the finished state
  }

  @Test func snapshotPercentageIsCorrect() async {
    let progress = TranslationProgress()
    await progress.configure(totalEntries: 4, languages: ["de"])

    await progress.recordCompletion(key: "a", language: "de", success: true)
    let snap = await progress.snapshot()
    #expect(snap.percentage == 25)
  }
}
