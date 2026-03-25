//
//  StringCatalog.swift
//
//
//  Created by Paul MacRory on 3/7/24.
//

import Foundation

public class StringCatalog: Codable {
  public let sourceLanguage: String
  public let version: String
  public var strings: [String: LocalizationGroup]

  public init(
    sourceLanguage: String,
    version: String = "1.0",
    strings: [String : LocalizationGroup] = [:]
  ) {
    self.sourceLanguage = sourceLanguage
    self.version = version
    self.strings = strings
  }
}

public class LocalizationGroup: Codable {
  public var comment: String?
  public var extractionState: String?
  public var localizations: [String: LocalizationUnit]?

  public init(
    comment: String? = nil,
    extractionState: String? = nil,
    localizations: [String : LocalizationUnit]? = nil
  ) {
    self.comment = comment
    self.extractionState = extractionState
    self.localizations = localizations
  }
}

public class LocalizationUnit: Codable {
  public var stringUnit: StringUnit?
  public var variations: VariationsUnit?
  public var substitutions: [String: SubstitutionsUnit]?

  public var isSupportedFormat: Bool {
    variations == nil && substitutions == nil
  }

  public var hasTranslation: Bool {
    stringUnit?.value.isEmpty == false
  }

  public init(
    stringUnit: StringUnit?,
    variations: VariationsUnit? = nil,
    substitutions: [String: SubstitutionsUnit]? = nil
  ) {
    self.stringUnit = stringUnit
    self.variations = variations
    self.substitutions = substitutions
  }
}

public class StringUnit: Codable {
  public var state: String
  public var value: String

  public init(
    state: String,
    value: String
  ) {
    self.state = state
    self.value = value
  }
}

public class VariationsUnit: Codable {
  public var plural: PluralVariation?
  public var device: DeviceVariation?
}

public class SubstitutionsUnit: Codable {
  public var formatSpecifier: String
  public var variations: VariationsUnit

  public init(formatSpecifier: String, variations: VariationsUnit) {
    self.formatSpecifier = formatSpecifier
    self.variations = variations
  }
}

public class PluralVariation: Codable {
  public var zero: VariationStringUnit?
  public var one: VariationStringUnit?
  public var two: VariationStringUnit?
  public var few: VariationStringUnit?
  public var many: VariationStringUnit?
  public var other: VariationStringUnit?
}

public class DeviceVariation: Codable {
  public var appletv: VariationStringUnit?
  public var applevision: VariationStringUnit?
  public var applewatch: VariationStringUnit?
  public var ipad: VariationStringUnit?
  public var iphone: VariationStringUnit?
  public var ipod: VariationStringUnit?
  public var mac: VariationStringUnit?
  public var other: VariationStringUnit?
}

public class VariationStringUnit: Codable {
  public var stringUnit: StringUnit
}
