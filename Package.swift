// swift-tools-version:5.3
import PackageDescription

let version = "1.24.0"
let checksum = "d31b5ee5ad0fcd235d75b7ba0fd70dc2b4f77930c6814602292e18622d2fd07c"
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

