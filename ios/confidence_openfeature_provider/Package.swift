// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "confidence_openfeature_provider",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "confidence-openfeature-provider", targets: ["confidence_openfeature_provider"])
    ],
    targets: [.target(name: "confidence_openfeature_provider")]
)
