// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TripSplitFeatures",
  platforms: [.iOS("26.0")],
  products: [
    .library(name: "TripSplitDesignSystem", targets: ["TripSplitDesignSystem"]),
    .library(name: "TripSplitSharedUI", targets: ["TripSplitSharedUI"]),
    .library(name: "TripSplitAppleAdapters", targets: ["TripSplitAppleAdapters"]),
    .library(name: "TripSplitTripsUI", targets: ["TripSplitTripsUI"]),
    .library(name: "TripSplitExpensesUI", targets: ["TripSplitExpensesUI"]),
    .library(name: "TripSplitConversionUI", targets: ["TripSplitConversionUI"]),
    .library(name: "TripSplitOnboardingUI", targets: ["TripSplitOnboardingUI"]),
    .library(name: "TripSplitAccountUI", targets: ["TripSplitAccountUI"]),
    .library(name: "TripSplitGlobeUI", targets: ["TripSplitGlobeUI"]),
  ],
  dependencies: [
    .package(path: "../TripSplitDomain"), .package(path: "../TripSplitInfrastructure"),
    .package(path: "../TripSplitApplication"),
  ],
  targets: [
    .target(
      name: "TripSplitDesignSystem",
      dependencies: [.product(name: "TripSplitDomain", package: "TripSplitDomain")]),
    .target(
      name: "TripSplitSharedUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        "TripSplitDesignSystem",
      ]),
    .target(
      name: "TripSplitAppleAdapters",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
      ]),
    .target(
      name: "TripSplitTripsUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        "TripSplitDesignSystem", "TripSplitSharedUI",
      ]),
    .target(
      name: "TripSplitExpensesUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitNetworking", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        "TripSplitDesignSystem", "TripSplitSharedUI",
      ]),
    .target(
      name: "TripSplitConversionUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitNetworking", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        .product(name: "TripSplitConversion", package: "TripSplitApplication"),
        "TripSplitDesignSystem", "TripSplitSharedUI",
      ]),
    .target(
      name: "TripSplitOnboardingUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        "TripSplitAppleAdapters", "TripSplitDesignSystem", "TripSplitSharedUI",
      ]),
    .target(
      name: "TripSplitAccountUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitNetworking", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitSync", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        "TripSplitAppleAdapters", "TripSplitDesignSystem", "TripSplitSharedUI",
      ]),
    .target(
      name: "TripSplitGlobeUI",
      dependencies: [
        .product(name: "TripSplitDomain", package: "TripSplitDomain"),
        .product(name: "TripSplitPersistence", package: "TripSplitInfrastructure"),
        .product(name: "TripSplitApplication", package: "TripSplitApplication"),
        "TripSplitDesignSystem",
      ]),
  ]
)
