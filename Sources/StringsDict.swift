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
  var strings: [String: LocalizationGroup]
}

class LocalizationGroup: Codable {
  var comment: String?
  var extractionState: String?
  var localizations: [String: LocalizationUnit]?
}

class LocalizationUnit: Codable {
  var stringUnit: StringUnit?
  var variations: VariationsUnit?
  var substitutions: [String: SubstitutionsUnit]?

  var isSupportedFormat: Bool {
    variations == nil && substitutions == nil
  }

  var hasTranslation: Bool {
    stringUnit?.value.isEmpty == false
  }

  init(
    stringUnit: StringUnit?,
    variations: VariationsUnit? = nil,
    substitutions: [String: SubstitutionsUnit]? = nil
  ) {
    self.stringUnit = stringUnit
    self.variations = variations
    self.substitutions = substitutions
  }
}

class StringUnit: Codable {
  var state: String
  var value: String

  init(
    state: String,
    value: String
  ) {
    self.state = state
    self.value = value
  }
}

class VariationsUnit: Codable {
  var plural: PluralVariation?
  var device: DeviceVariation?
}

class SubstitutionsUnit: Codable {
  var formatSpecifier: String
  var variations: VariationsUnit
}

class PluralVariation: Codable {
  var zero: VariationStringUnit?
  var one: VariationStringUnit?
  var two: VariationStringUnit?
  var few: VariationStringUnit?
  var many: VariationStringUnit?
  var other: VariationStringUnit?
}

class DeviceVariation: Codable {
  var appletv: VariationStringUnit?
  var applevision: VariationStringUnit?
  var applewatch: VariationStringUnit?
  var ipad: VariationStringUnit?
  var iphone: VariationStringUnit?
  var ipod: VariationStringUnit?
  var mac: VariationStringUnit?
  var other: VariationStringUnit?
}

class VariationStringUnit: Codable {
  var stringUnit: StringUnit
}
