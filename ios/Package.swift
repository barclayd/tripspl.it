// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TripSplitDomain", platforms: [.macOS(.v15)],
  products: [.library(name: "TripSplitDomain", targets: ["TripSplitDomain"])],
  targets: [
    .target(name: "TripSplitDomain", path: "TripSplit/Domain", resources: [.process("Resources")]),
    .testTarget(
      name: "TripSplitDomainTests", dependencies: ["TripSplitDomain"], path: "DomainTests"),
  ])
