// swift-tools-version:5.3
import PackageDescription

let version = "1.24.0"
let checksum = "acc765a67e6011fdd7cd8fe86b35b05a69e1ef42867ba3828a820a431f47a982"
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

