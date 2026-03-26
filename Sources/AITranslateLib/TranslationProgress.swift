//
//  TranslationProgress.swift
//
//
//  Created by AI on 3/25/26.
//

import Foundation

public enum LanguageStatus: Sendable {
    case pending
    case active
    case done
}

public struct LanguageState: Sendable {
    public let language: String
    public var completed: Int = 0
    public var failed: Int = 0
    public var total: Int = 0
    public var status: LanguageStatus = .pending
}

public struct ProgressSnapshot: Sendable {
    public let languages: [LanguageState]
    public let totalEntries: Int
    public let totalCompleted: Int
    public let totalFailed: Int
    public let warningCount: Int
    public let errorCount: Int
    public let elapsedSeconds: TimeInterval
    public let isFinished: Bool

    public var percentage: Int {
        guard totalEntries > 0 else { return 0 }
        return min(100, Int(Double(totalCompleted) / Double(totalEntries) * 100))
    }
}

public actor TranslationProgress {
    private var languageStates: [String: LanguageState] = [:]
    private var languageOrder: [String] = []
    private var totalEntries: Int = 0
    private var totalCompleted: Int = 0
    private var totalFailed: Int = 0
    private var warningCount: Int = 0
    private var errorCount: Int = 0
    private var startTime: Date = Date()
    private var finished: Bool = false

    public init() {}

    public func configure(totalEntries: Int, languages: [String]) {
        self.totalEntries = totalEntries
        self.languageOrder = languages
        self.startTime = Date()
        self.finished = false
        self.totalCompleted = 0
        self.totalFailed = 0
        self.warningCount = 0
        self.errorCount = 0

        for lang in languages {
            languageStates[lang] = LanguageState(
                language: lang,
                total: totalEntries,
                status: .pending
            )
        }
    }

    public func recordCompletion(key: String, language: String, success: Bool) {
        guard var state = languageStates[language] else { return }
        if state.status == .pending {
            state.status = .active
        }
        state.completed += 1
        if !success {
            state.failed += 1
            totalFailed += 1
        }
        if state.completed >= state.total {
            state.status = .done
        }
        languageStates[language] = state
        totalCompleted += 1
    }

    public func recordWarning() {
        warningCount += 1
    }

    public func recordError() {
        errorCount += 1
    }

    public func markFinished() {
        finished = true
        for lang in languageOrder {
            languageStates[lang]?.status = .done
        }
    }

    public func snapshot() -> ProgressSnapshot {
        let states = languageOrder.compactMap { languageStates[$0] }
        return ProgressSnapshot(
            languages: states,
            totalEntries: totalEntries,
            totalCompleted: totalCompleted,
            totalFailed: totalFailed,
            warningCount: warningCount,
            errorCount: errorCount,
            elapsedSeconds: Date().timeIntervalSince(startTime),
            isFinished: finished
        )
    }
}
