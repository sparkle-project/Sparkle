// swift-tools-version:5.3
import PackageDescription

let version = "2.0.0"
let checksum = "760a229721e04427783f9c43f67a0257722173c8db7e7f7df2d1387d8a3f6dbf"
let url = "https://github.com/sparkle-project/Sparkle/releases/download/\(version)/Sparkle-SPM-\(version).zip"

let package = Package(
    name: "Sparkle",
    platforms: [.macOS(.v10_11)],
    products: [
        .library(
            name: "Sparkle",
            targets: ["Sparkle"])
    ],
    targets: [
        .binaryTarget(
            name: "Sparkle",
            url: url,
            checksum: checksum
        )
    ]
)
