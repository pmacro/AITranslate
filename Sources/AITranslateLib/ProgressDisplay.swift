//
//  ProgressDisplay.swift
//
//
//  Created by AI on 3/25/26.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Renders a live-updating bordered panel to stderr using the alternate screen buffer.
/// Uses the same mechanism as vim/htop/less — no cursor-up needed.
public final class ProgressDisplay: Sendable {
    private let progress: TranslationProgress
    private let renderTask: SendableBox<Task<Void, Never>?>
    private let minWidth = 42

    public init(progress: TranslationProgress) {
        self.progress = progress
        self.renderTask = SendableBox(nil)
    }

    public func start() {
        // Switch to alternate screen buffer + hide cursor
        writeStderr("\u{1B}[?1049h\u{1B}[?25l")

        // Install SIGINT handler to restore terminal state before exit
        signal(SIGINT) { _ in
            var buf = Array("\u{1B}[?25h\u{1B}[?1049l\n".utf8)
            write(STDERR_FILENO, &buf, buf.count)
            _Exit(130)
        }

        let task = Task { [self] in
            while !Task.isCancelled {
                let snap = await self.progress.snapshot()
                self.render(snap)
                if snap.isFinished { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        renderTask.value = task
    }

    public func stop() async -> ProgressSnapshot {
        renderTask.value?.cancel()
        await renderTask.value?.value
        renderTask.value = nil

        // Final render
        let snap = await progress.snapshot()
        render(snap)

        // Brief pause so the user can see the completed state
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Show cursor + switch back to main screen buffer
        writeStderr("\u{1B}[?25h\u{1B}[?1049l")
        signal(SIGINT, SIG_DFL)

        return snap
    }

    private func terminalWidth() -> Int {
        var ws = winsize()
        if ioctl(STDERR_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0 {
            return max(Int(ws.ws_col), minWidth)
        }
        return 80
    }

    private func terminalHeight() -> Int {
        var ws = winsize()
        if ioctl(STDERR_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_row > 0 {
            return Int(ws.ws_row)
        }
        return 24
    }

    func render(_ snapshot: ProgressSnapshot) {
        let width = terminalWidth()
        var lines: [String] = []

        let title = " AITranslate Progress "
        let topBorder = buildTopBorder(width: width, title: title)
        lines.append(topBorder)

        // Progress bar line
        let pct = snapshot.percentage
        let barWidth = max(10, width - 10)
        let filled = Int(Double(pct) / 100.0 * Double(barWidth))
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barWidth - filled)
        let pctStr = String(format: "%3d%%", pct)
        lines.append(padLine("  \(bar) \(pctStr)", width: width))

        // Blank separator
        lines.append(padLine("", width: width))

        // Stats line
        let elapsed = formatElapsed(snapshot.elapsedSeconds)
        let statsLeft = "  Elapsed: \(elapsed)"
        let statsRight = "warn: \(snapshot.warningCount)  err: \(snapshot.errorCount)  "
        let statsGap = max(1, width - 2 - displayWidth(statsLeft) - displayWidth(statsRight))
        lines.append("│" + statsLeft + String(repeating: " ", count: statsGap) + statsRight + "│")

        // Blank separator
        lines.append(padLine("", width: width))

        // Per-language header
        lines.append(padLine("  Language   Status       Progress", width: width))
        let divider = "  " + String(repeating: "─", count: width - 4)
        lines.append(padLine(divider, width: width))

        // Per-language rows
        for lang in snapshot.languages {
            let langLabel = padRight(lang.language, to: 9)
            let statusIcon: String
            let statusLabel: String
            switch lang.status {
            case .pending:
                statusIcon = "-"
                statusLabel = "pending"
            case .active:
                statusIcon = "*"
                statusLabel = "active "
            case .done:
                statusIcon = "+"
                statusLabel = "done   "
            }
            let langPct = lang.total > 0 ? Int(Double(lang.completed) / Double(lang.total) * 100) : 0
            let langBarWidth = max(5, width - 36)
            let langFilled = Int(Double(langPct) / 100.0 * Double(langBarWidth))
            let langBar = String(repeating: "█", count: langFilled) + String(repeating: "░", count: langBarWidth - langFilled)
            let failStr = lang.failed > 0 ? " (\(lang.failed) failed)" : ""
            let row = "  \(langLabel) \(statusIcon) \(statusLabel) \(langBar) \(String(format: "%3d%%", langPct))\(failStr)"
            lines.append(padLine(row, width: width))
        }

        // Bottom border
        lines.append("└" + String(repeating: "─", count: width - 2) + "┘")

        // Cursor home (1,1) then write the entire panel
        var buf = "\u{1B}[H"
        for line in lines {
            buf += line + "\u{1B}[K\n"  // clear rest of line in case terminal is wider now
        }

        writeStderr(buf)
    }

    private func buildTopBorder(width: Int, title: String) -> String {
        let titleLen = displayWidth(title)
        let remaining = width - 2 - titleLen
        let leftDash = max(1, remaining / 2)
        let rightDash = max(1, remaining - leftDash)
        return "┌" + String(repeating: "─", count: leftDash) + title + String(repeating: "─", count: rightDash) + "┐"
    }

    private func padLine(_ content: String, width: Int) -> String {
        let visibleLen = displayWidth(content)
        let padding = max(0, width - 2 - visibleLen)
        return "│" + content + String(repeating: " ", count: padding) + "│"
    }

    private func padRight(_ str: String, to length: Int) -> String {
        let w = displayWidth(str)
        if w >= length { return str }
        return str + String(repeating: " ", count: length - w)
    }

    private func displayWidth(_ string: String) -> Int {
        var width = 0
        for scalar in string.unicodeScalars {
            let w = wcwidth(wchar_t(scalar.value))
            width += w > 0 ? Int(w) : (w == 0 ? 0 : 1)
        }
        return width
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// Thread-safe mutable box for use inside Sendable types.
final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private func writeStderr(_ string: String) {
    let data = Array(string.utf8)
    var offset = 0
    while offset < data.count {
        let result = data[offset...].withUnsafeBufferPointer { ptr in
            write(STDERR_FILENO, ptr.baseAddress!, ptr.count)
        }
        if result <= 0 { break }
        offset += result
    }
}

// MARK: - RichProgressReporter

/// Full TUI progress reporter combining TranslationProgress actor + ProgressDisplay renderer.
public actor RichProgressReporter: ProgressReporter {
    private let progress: TranslationProgress
    private let display: ProgressDisplay
    private var verboseMessages: [String] = []
    private let verbose: Bool

    public init(verbose: Bool = false) {
        let progress = TranslationProgress()
        self.progress = progress
        self.display = ProgressDisplay(progress: progress)
        self.verbose = verbose
    }

    public func translationStarted(totalEntries: Int, languages: [String]) async {
        await progress.configure(totalEntries: totalEntries, languages: languages)
        display.start()
    }

    public func translationCompleted(key: String, language: String, success: Bool) async {
        await progress.recordCompletion(key: key, language: language, success: success)
    }

    public func verboseLog(_ message: String) {
        verboseMessages.append(message)
    }

    public func warning(_ message: String) {
        if verbose {
            verboseMessages.append("[⚠️] \(message)")
        }
        Task { await progress.recordWarning() }
    }

    public func error(_ message: String) {
        if verbose {
            verboseMessages.append("[❌] \(message)")
        }
        Task { await progress.recordError() }
    }

    public func finished() async {
        await progress.markFinished()
        let snap = await display.stop()

        // Print summary to main screen after alternate buffer exits
        let elapsed = formatElapsed(snap.elapsedSeconds)
        print("[✅] Translation complete (\(elapsed) elapsed, \(snap.warningCount) warnings, \(snap.errorCount) errors)")

        // Print buffered verbose messages after panel teardown
        for msg in verboseMessages {
            print(msg)
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
