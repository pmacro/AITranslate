//
//  ProgressReporter.swift
//
//
//  Created by AI on 3/25/26.
//

import Foundation

public protocol ProgressReporter: Sendable {
    func translationStarted(totalEntries: Int, languages: [String]) async
    func translationCompleted(key: String, language: String, success: Bool) async
    func warning(_ message: String) async
    func error(_ message: String) async
    func finished() async
}

/// Simple text-based reporter for non-TTY environments (pipes, CI, --no-tui).
/// Replicates the original print-based output.
public actor SimpleProgressReporter: ProgressReporter {
    private var totalEntries = 0
    private var entriesCompleted = 0
    private var previousPercentage: Int = -1
    private var startTime = Date()

    public init() {}

    public func translationStarted(totalEntries: Int, languages: [String]) {
        self.totalEntries = totalEntries
        self.startTime = Date()
        self.entriesCompleted = 0
        self.previousPercentage = -1
    }

    public func translationCompleted(key: String, language: String, success: Bool) {
        entriesCompleted += 1
        guard totalEntries > 0 else { return }
        let pct = Int(Double(entriesCompleted) / Double(totalEntries) * 100)
        if pct != previousPercentage, pct % 10 == 0 {
            print("[⏳] \(pct)%")
            previousPercentage = pct
        }
    }

    public func warning(_ message: String) {
        print("[⚠️] \(message)")
    }

    public func error(_ message: String) {
        print("[❌] \(message)")
    }

    public func finished() {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        let elapsed = formatter.string(from: Date().timeIntervalSince(startTime)) ?? "unknown"
        print("[✅] 100% \n[⏰] Translations time: \(elapsed)")
    }
}
