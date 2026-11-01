// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TripSplitInfrastructure",
  platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
  products: [
    .library(name: "TripSplitNetworking", targets: ["TripSplitNetworking"]),
    .library(name: "TripSplitPersistence", targets: ["TripSplitPersistence"]),
    .library(name: "TripSplitSync", targets: ["TripSplitSync"]),
    .library(name: "TripSplitCompanion", targets: ["TripSplitCompanion"]),
  ],
  dependencies: [.package(path: "../TripSplitDomain")],
  targets: [
    .target(
      name: "TripSplitNetworking",
      dependencies: [.product(name: "TripSplitDomain", package: "TripSplitDomain")]),
    .target(
      name: "TripSplitPersistence",
      dependencies: [.product(name: "TripSplitDomain", package: "TripSplitDomain")]),
    .target(
      name: "TripSplitSync",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"), "TripSplitNetworking",
        "TripSplitPersistence",
      ]),
    .target(
      name: "TripSplitCompanion",
      dependencies: [.product(name: "TripSplitDomain", package: "TripSplitDomain")]),
    .testTarget(
      name: "TripSplitCompanionTests",
      dependencies: [
        "TripSplitCompanion", .product(name: "TripSplitDomain", package: "TripSplitDomain"),
      ]),
  ]
)
