// swift-tools-version:5.3
import PackageDescription

let version = "1.24.0"
let checksum = "47e985f48abc1470673db2dca0c0b6ded5dfa80fa32a1b33bc014cc310f75c1a"
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

