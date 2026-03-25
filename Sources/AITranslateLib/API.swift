//
//  API.swift
//
//
//  Created by Paul MacRory on 3/15/24.
//

import OpenAI
import Foundation

enum APIRegistry {
  case test
  case production

  static var current: APIRegistry {
    if NSClassFromString("XCTest") != nil {
      return .test
    }

    return .production
  }

  func create(with configuration: OpenAI.Configuration) -> API {
    switch self {
    case .production:
      OpenAI(configuration: configuration)
    case .test:
      MockAPI()
    }
 }
}

protocol API {
  func chats(
    query: ChatQuery
  ) async throws -> ChatResult
}

extension OpenAI: API {}

class MockAPI: API {
  var responseContent = "mock translation"
  var error: Error?
  private(set) var receivedQueries: [ChatQuery] = []

  func chats(
      query: ChatQuery
  ) async throws -> ChatResult {
    receivedQueries.append(query)
    if let error { throw error }
    let escaped = responseContent
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
    let json = """
    {"id":"mock","object":"chat.completion","created":1,"model":"mock","choices":[{"index":0,"message":{"role":"assistant","content":"\(escaped)"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """
    return try JSONDecoder().decode(ChatResult.self, from: json.data(using: .utf8)!)
  }
}
