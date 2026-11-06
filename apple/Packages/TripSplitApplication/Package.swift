// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TripSplitApplication",
  platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
  products: [
    .library(name: "TripSplitApplication", targets: ["TripSplitApplication"]),
    .library(name: "TripSplitConversion", targets: ["TripSplitConversion"]),
    .library(name: "TripSplitCompanionHost", targets: ["TripSplitCompanionHost"]),
    .library(name: "TripSplitWatchModel", targets: ["TripSplitWatchModel"]),
    .library(name: "TripSplitWidgetModel", targets: ["TripSplitWidgetModel"]),
  ],
  dependencies: [
    .package(path: "../TripSplitDomain"), .package(path: "../TripSplitInfrastructure"),
  ],
  targets: [
    .target(
      name: "TripSplitApplication",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitNetworking", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
      ]),
    .target(
      name: "TripSplitConversion",
      dependencies: [.product(name: "TripSplitDomain", package: "TripSplitDomain")]),
    .target(
      name: "TripSplitCompanionHost",
      dependencies: [
        "TripSplitApplication", .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitCompanion", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
      ]),
    .target(
      name: "TripSplitWatchModel",
      dependencies: [
        "TripSplitApplication", .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitCompanion", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitNetworking", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
      ]),
    .target(
      name: "TripSplitWidgetModel",
      dependencies: [
        "TripSplitApplication", "TripSplitWatchModel",
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitCompanion", package: "TripSplitInfrastructure"),
      ]),
    .testTarget(
      name: "TripSplitApplicationTests",
      dependencies: [
        "TripSplitApplication", "TripSplitConversion", "TripSplitCompanionHost",
        "TripSplitWatchModel", "TripSplitWidgetModel",
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitCompanion", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitNetworking", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
      ], resources: [.copy("Fixtures")]),
  ]
)
