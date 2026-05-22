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
  targets: [
    .executableTarget(
      name: "TokMonApp",
      path: "Sources/TokMonApp",
      linkerSettings: [
        .linkedLibrary("sqlite3"),
      ],
    ),
    .testTarget(
      name: "TokMonAppTests",
      dependencies: ["TokMonApp"],
      path: "Tests/TokMonAppTests",
    ),
  ],
)
