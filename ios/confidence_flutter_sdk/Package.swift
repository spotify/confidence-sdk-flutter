// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "confidence_flutter_sdk",
    platforms: [
        .iOS("14.0"),
    ],
    products: [
        .library(name: "confidence-flutter-sdk", targets: ["confidence_flutter_sdk"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "confidence_flutter_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
