//
//  AITranslate.swift
//
//
//  Created by Paul MacRory on 3/7/24.
//

import ArgumentParser
import OpenAI
import Foundation

// 简单的异步信号量，用于控制并发数量
actor AsyncSemaphore {
    private var permits: Int
    private var waitQueue: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.permits = value
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }

    func release() {
        if !waitQueue.isEmpty {
            let continuation = waitQueue.removeFirst()
            continuation.resume()
        } else {
            permits += 1
        }
    }
}

// 异步安全的计数器，用于进度跟踪
actor ProgressCounter {
    private var count: Int = 0
    private let total: Int
    
    init(total: Int) {
        self.total = total
    }
    
    func increment() -> (current: Int, percentage: Int) {
        count += 1
        let percentage = Int((Double(count) / Double(total)) * 100)
        return (count, percentage)
    }
    
    var currentCount: Int { count }
}

// 超时函数
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

struct TimeoutError: Error {
    let localizedDescription = "操作超时"
}

// MARK: - Array chunk 工具
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

@main
struct AITranslate: AsyncParsableCommand {
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

  static func gatherLanguages(from input: String) -> [String] {
    input.split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespaces) }
  }
  
  // 从 .env 文件读取环境变量
  static func loadEnvFile() -> [String: String] {
    let envPath = FileManager.default.currentDirectoryPath + "/.env"
    let envURL = URL(fileURLWithPath: envPath)
    
    guard let envContent = try? String(contentsOf: envURL) else {
      return [:]
    }
    
    var envVars: [String: String] = [:]
    let lines = envContent.components(separatedBy: .newlines)
    
    for line in lines {
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      
      // 跳过空行和注释行
      if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
        continue
      }
      
      // 分割键值对
      let components = trimmedLine.components(separatedBy: "=")
      if components.count >= 2 {
        let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = components.dropFirst().joined(separator: "=")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) // 移除引号
        
        envVars[key] = value
      }
    }
    
    return envVars
  }

  @Argument(transform: URL.init(fileURLWithPath:))
  var inputFile: URL

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("A comma separated list of language codes (must match the language codes used by xcstrings)"), 
    transform: { AITranslate.gatherLanguages(from: $0) }
  )
  var languages: [String] = []

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("Your OpenAI API key, see: https://platform.openai.com/api-keys")
  )
  var openAIKey: String = ""
    
  @Option(
    name: .customLong("host"),
    help: ArgumentHelp("Your OpenAI Proxy Host")
  )
  var openAIHost: String = ""

  @Option(
    name: .shortAndLong,
    help: ArgumentHelp("Your Model, see: https://platform.openai.com/docs/models, e,g (gpt-3.5-turbo, gpt-4o-mini, gpt-4o)")
  )
  var model: String = ""

  @Flag(name: .shortAndLong)
  var verbose: Bool = false

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp("By default a backup of the input will be created. When this flag is provided, the backup is skipped.")
  )
  var skipBackup: Bool = false

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp("Forces all strings to be translated, even if an existing translation is present.")
  )
  var force: Bool = false

  @Option(
    name: .customLong("concurrency"),
    help: ArgumentHelp("Maximum concurrent translation requests (default: 5)")
  )
  var concurrency: Int = 5


  // 处理参数优先级的属性
  private var resolvedLanguages: [String] = []
  private var resolvedOpenAIKey: String = ""
  private var resolvedOpenAIHost: String = ""
  private var resolvedModel: String = ""
  private var resolvedConcurrency: Int = 5

  lazy var openAI: OpenAI = {
    let configuration = OpenAI.Configuration(
      token: resolvedOpenAIKey,
      organizationIdentifier: nil,
      host: resolvedOpenAIHost,
      timeoutInterval: 30.0  // 减少超时时间到30秒
    )

    return OpenAI(configuration: configuration)
  }()

  var numberOfTranslationsProcessed = 0

  mutating func run() async throws {
    // 加载 .env 文件
    let envVars = Self.loadEnvFile()
    
    // 解析参数优先级：命令行 > .env
    resolvedLanguages = languages.isEmpty ? 
      Self.gatherLanguages(from: envVars["LANGUAGES"] ?? "") : languages
    
    resolvedOpenAIKey = openAIKey.isEmpty ? 
      (envVars["OPENAI_API_KEY"] ?? "") : openAIKey
    
    resolvedOpenAIHost = openAIHost.isEmpty ? 
      (envVars["OPENAI_HOST"] ?? "api.openai.com") : openAIHost
    
    resolvedModel = model.isEmpty ? 
      (envVars["MODEL"] ?? "gpt-4o-mini") : model
    
    // 解析并发数量，默认为5
    if let concurrencyStr = envVars["CONCURRENCY"], let concurrency = Int(concurrencyStr) {
      resolvedConcurrency = max(1, min(concurrency, 20)) // 限制在1-20之间
    } else {
      resolvedConcurrency = max(1, min(concurrency, 20))
    }
    
    
    // 验证必要参数
    guard !resolvedLanguages.isEmpty else {
      throw ValidationError("Languages must be specified either via command line (-l) or .env file (LANGUAGES)")
    }
    
    guard !resolvedOpenAIKey.isEmpty else {
      throw ValidationError("OpenAI API key must be specified either via command line (-k) or .env file (OPENAI_API_KEY)")
    }
    
    if verbose {
      print("[📁] Using languages: \(resolvedLanguages.joined(separator: ", "))")
      print("[🤖] Using model: \(resolvedModel)")
      print("[🌐] Using host: \(resolvedOpenAIHost)")
      print("[⚡] Using concurrency: \(resolvedConcurrency)")
    }

    do {
      let dict = try JSONDecoder().decode(
        StringsDict.self,
        from: try Data(contentsOf: inputFile)
      )

      let start = Date()
      let totalLanguages = resolvedLanguages.count
      
      if verbose {
        print("[📊] 总计需要翻译: \(totalLanguages) 个语言")
        print("[⚡] 并发数: \(resolvedConcurrency)")
      }
      
      // 按语言依次翻译，每个语言完成后立即保存
      for (index, lang) in resolvedLanguages.enumerated() {
        if verbose {
          print("[🚀] 开始翻译语言: \(lang) (\(dict.strings.count) 个条目)")
        }
        
        // 翻译当前语言的所有条目
        try await processLanguage(lang, dict: dict, sourceLanguage: dict.sourceLanguage)
        
        // 每个语言完成后立即保存
        try save(dict)
        
        // 更新进度显示
        let percentage = Int((Double(index + 1) / Double(totalLanguages)) * 100)
        print("[⏳] 已完成 \(index + 1)/\(totalLanguages) 个语言 (\(percentage)%) - 当前: \(lang)")
      }

      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = [.hour, .minute, .second]
      formatter.unitsStyle = .full
      let formattedString = formatter.string(from: Date().timeIntervalSince(start))!

      print("[✅] 所有语言翻译完成 \n[⏰] 总耗时: \(formattedString)")
    } catch let error {
      throw error
    }
  }
  
  // 翻译单个语言的所有条目，使用分批并发处理
  mutating func processLanguage(_ lang: String, dict: StringsDict, sourceLanguage: String) async throws {
    // 提前提取需要的值，避免在闭包中访问self
    let forceFlag = force
    let verboseFlag = verbose
    let openAIClient = openAI
    let model = resolvedModel
    
    let totalEntries = dict.strings.count
    let progressCounter = ProgressCounter(total: totalEntries)
    
    // 将条目按并发数分批
    let entries = Array(dict.strings)
    let chunks = entries.chunked(into: resolvedConcurrency)
    
    for chunk in chunks {
      // 批次内并发处理
      try await withThrowingTaskGroup(of: Void.self) { group in
        for entry in chunk {
          group.addTask {
            try await Self.translateEntry(
              entry: entry,
              lang: lang,
              sourceLanguage: sourceLanguage,
              forceFlag: forceFlag,
              verboseFlag: verboseFlag,
              openAIClient: openAIClient,
              model: model,
              progressCounter: progressCounter,
              totalEntries: totalEntries
            )
          }
        }
        try await group.waitForAll()
      }
    }
  }
  
  // 翻译单个条目
  private static func translateEntry(
    entry: (key: String, value: LocalizationGroup),
    lang: String,
    sourceLanguage: String,
    forceFlag: Bool,
    verboseFlag: Bool,
    openAIClient: OpenAI,
    model: String,
    progressCounter: ProgressCounter,
    totalEntries: Int
  ) async throws {
    let localizationEntries = entry.value.localizations ?? [:]
    let unit = localizationEntries[lang]

    // Nothing to do.
    if let unit, unit.hasTranslation, forceFlag == false { return }
    
    // Skip the ones with variations/substitutions since they are not supported.
    if let unit, unit.isSupportedFormat == false {
      print("[⚠️] Unsupported format in entry with key: \(entry.key)")
      return
    }

    // The source text can either be the key or an explicit value in the `localizations`
    // dictionary keyed by `sourceLanguage`.
    let sourceText = localizationEntries[sourceLanguage]?.stringUnit?.value ?? entry.key

    let result: String?
    if entry.value.shouldTranslate != false {
      // 内联翻译逻辑
      if sourceText.isEmpty ||
          sourceText.trimmingCharacters(
            in: .whitespacesAndNewlines
              .union(.symbols)
              .union(.controlCharacters)
          ).isEmpty {
        result = sourceText
      } else {
        var translationRequest = "<source>\(sourceLanguage)</source>"
        translationRequest += "<target>\(lang)</target>"
        translationRequest += "<original>\(sourceText)</original>"

        if let context = entry.value.comment {
          translationRequest += "<context>\(context)</context>"
        }

        let query = ChatQuery(
          messages: [
            .init(role: .system, content: Self.systemPrompt)!,
            .init(role: .user, content: translationRequest)!
          ],
          model: model
        )

        do {
          // 添加超时机制
          let translationResult = try await withTimeout(seconds: 30) {
            try await openAIClient.chats(query: query)
          }
          
          result = translationResult.choices.first?.message.content?.string ?? sourceText

          if verboseFlag {
            print("[\(lang)] " + sourceText + " -> " + (result ?? ""))
          }
        } catch let error {
          print("[❌] Failed to translate \(sourceText) into \(lang)")

          if verboseFlag {
            print("[💥]" + error.localizedDescription)
          }

          result = nil
        }
      }
    } else {
      result = entry.key
      if verboseFlag {
        print("[\(lang)] " + entry.key + " -> skip")
      }
    }

    var newEntries = localizationEntries
    newEntries[lang] = LocalizationUnit(
      stringUnit: StringUnit(
        state: result == nil ? "error" : "translated",
        value: result ?? ""
      )
    )
    entry.value.localizations = newEntries
    
    // 更新进度（异步安全）
    let (current, percentage) = await progressCounter.increment()
    
    // 每翻译一条就打印一条
    print("[📝] \(lang): \(current)/\(totalEntries) (\(percentage)%)")
  }
  
  // 处理单个条目的翻译
  mutating func processEntry(
    key: String,
    localizationGroup: LocalizationGroup,
    sourceLanguage: String,
    targetLanguage: String
  ) async throws {
    let localizationEntries = localizationGroup.localizations ?? [:]
    let unit = localizationEntries[targetLanguage]

    // Nothing to do.
    if let unit, unit.hasTranslation, force == false { return }
    
    // Skip the ones with variations/substitutions since they are not supported.
    if let unit, unit.isSupportedFormat == false {
      print("[⚠️] Unsupported format in entry with key: \(key)")
      return
    }

    // The source text can either be the key or an explicit value in the `localizations`
    // dictionary keyed by `sourceLanguage`.
    let sourceText = localizationEntries[sourceLanguage]?.stringUnit?.value ?? key

    let result: String?
    if localizationGroup.shouldTranslate != false {
      result = try await performTranslation(
        sourceText,
        from: sourceLanguage,
        to: targetLanguage,
        context: localizationGroup.comment,
        openAI: openAI
      )
    } else {
      result = key
      if verbose {
        print("[\(targetLanguage)] \(key) -> skip")
      }
    }

    var newEntries = localizationEntries
    newEntries[targetLanguage] = LocalizationUnit(
      stringUnit: StringUnit(
        state: result == nil ? "error" : "translated",
        value: result ?? ""
      )
    )
    localizationGroup.localizations = newEntries
  }


  func save(_ dict: StringsDict) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    let data = try encoder.encode(dict)

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
    openAI: OpenAI
  ) async throws -> String? {

    // Skip text that is generally not translated.
    if text.isEmpty ||
        text.trimmingCharacters(
          in: .whitespacesAndNewlines
            .union(.symbols)
            .union(.controlCharacters)
        ).isEmpty {
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
      model: resolvedModel
    )

    do {
      let result = try await openAI.chats(query: query)
      let translation = result.choices.first?.message.content?.string ?? text

      if verbose {
        print("[\(target)] " + text + " -> " + translation)
      }

      return translation
    } catch let error {
      print("[❌] Failed to translate \(text) into \(target)")

      if verbose {
        print("[💥]" + error.localizedDescription)
      }

      return nil
    }
  }
}
