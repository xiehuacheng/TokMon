// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AgentMonMac",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "AgentMon", targets: ["AgentMonApp"]),
  ],
  targets: [
    .executableTarget(
      name: "AgentMonApp",
      path: "Sources/AgentMonApp",
      linkerSettings: [
        .linkedLibrary("sqlite3"),
      ],
    ),
    .testTarget(
      name: "AgentMonAppTests",
      dependencies: ["AgentMonApp"],
      path: "Tests/AgentMonAppTests",
    ),
  ],
)
