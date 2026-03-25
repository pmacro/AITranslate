// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "ai-translate",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "ai-translate", targets: ["AITranslate"]),
    .library(name: "AITranslateLib", targets: ["AITranslateLib"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main")
  ],
  targets: [
    .target(
      name: "AITranslateLib",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "OpenAI", package: "OpenAI"),
      ]
    ),
    .executableTarget(
      name: "AITranslate",
      dependencies: [
        "AITranslateLib"
      ]
    ),
    .testTarget(
      name: "AITranslateTests",
      dependencies: ["AITranslate", "AITranslateLib"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
