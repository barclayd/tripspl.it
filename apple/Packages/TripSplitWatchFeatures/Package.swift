// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TripSplitWatchFeatures",
  platforms: [.watchOS("26.0")],
  products: [
    .library(name: "TripSplitWatchDesign", targets: ["TripSplitWatchDesign"]),
    .library(name: "TripSplitWatchUI", targets: ["TripSplitWatchUI"]),
  ],
  dependencies: [
    .package(path: "../TripSplitDomain"), .package(path: "../TripSplitApplication"),
  ],
  targets: [
    .target(
      name: "TripSplitWatchDesign",
      dependencies: [.product(name: "TripSplitDomain", package: "TripSplitDomain")]),
    .target(
      name: "TripSplitWatchUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitWatchModel", package: "TripSplitApplication"),
        "TripSplitWatchDesign",
      ]),
  ]
)
