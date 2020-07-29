// swift-tools-version:5.3
import PackageDescription

let version = "VERSION_PLACEHOLDER"
let checksum = "CHECKSUM_PLACEHOLDER"
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

