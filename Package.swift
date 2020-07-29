// swift-tools-version:5.3
import PackageDescription

let version = "1.24.0"
let checksum = "64aed3dcc129ba7811fea026ac1bfbe512b7dc93ca6a4a444424cfde6a2c66a5"
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

