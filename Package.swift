// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "pdfsnip",
  platforms: [.macOS(.v10_11)],
  products: [
    .executable(name: "pdfsnip", targets: ["pdfsnip"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "0.3.1"),
  ],
  targets: [
    .target(
      name: "pdfsnip",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]),
  ]
)
