//
//  StringsDict.swift
//
//
//  Created by Paul MacRory on 3/7/24.
//

import Foundation

class StringsDict: Codable {
  let sourceLanguage: String
  let version: String
  var strings: [String: Localizations]
}

class Localizations: Codable {
  let comment: String?
  let extractionState: String?
  var localizations: [String: LocalizationUnit]?
}

class LocalizationUnit: Codable {
  let stringUnit: StringUnit

  init(stringUnit: StringUnit) {
    self.stringUnit = stringUnit
  }
}

class StringUnit: Codable {
  let state: String
  let value: String

  init(state: String, value: String) {
    self.state = state
    self.value = value
  }
}
