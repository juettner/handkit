// swift-tools-version: 5.9
//
// HandKit: handwriting as data, and a pen that writes it.
//
// For a Java person: this file is the pom.xml. It names one library
// ("HandKit") built from Sources/HandKit, and one test target. There are no
// dependencies. An app adds the package in Xcode (File > Add Package
// Dependencies, or "Add Local..." for a folder on disk) and then writes
// `import HandKit`.
//
// `platforms` are minimums, not a list of where it runs. The pen and the
// data build for iOS and macOS; the drawing page (HandEditor) is iOS only.

import PackageDescription

let package = Package(
    name: "HandKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HandKit", targets: ["HandKit"]),
    ],
    targets: [
        .target(name: "HandKit"),
        .testTarget(name: "HandKitTests", dependencies: ["HandKit"]),
    ]
)
