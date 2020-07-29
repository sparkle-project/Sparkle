// swift-tools-version:5.3
import PackageDescription

let version = "1.24.0"
let checksum = "ed8effb7d9faa40bb2ff48d4d2194707660dbd56507c496cd5ec2b07ec8dc7eb"
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

