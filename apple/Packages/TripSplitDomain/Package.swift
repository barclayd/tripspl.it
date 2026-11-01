// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TripSplitDomain",
  platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
  products: [
    .library(name: "TripSplitDomain", targets: ["TripSplitDomain"])
  ],
  dependencies: [],
  targets: [
    .target(name: "TripSplitDomain", dependencies: [], resources: [.process("Resources")]),
    .testTarget(name: "TripSplitDomainTests", dependencies: ["TripSplitDomain"]),
  ]
)
