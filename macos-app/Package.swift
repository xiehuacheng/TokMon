// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "TokMonMac",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "TokMon", targets: ["TokMonApp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
  ],
  targets: [
    .executableTarget(
      name: "TokMonApp",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/TokMonApp",
      linkerSettings: [
        .linkedLibrary("sqlite3"),
        .linkedFramework("CoreServices"),
        .linkedFramework("Security"),
      ],
    ),
    .testTarget(
      name: "TokMonAppTests",
      dependencies: ["TokMonApp"],
      path: "Tests/TokMonAppTests",
    ),
  ],
)
