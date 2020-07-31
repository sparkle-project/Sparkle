// swift-tools-version:5.3
import PackageDescription

let version = "2.0.0"
let checksum = "c37a2b9b19743f4fe0d01f3e1782f799421b3e07ff46fc1ab8fe1f7e818c4437"
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
