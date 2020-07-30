// swift-tools-version:5.3
import PackageDescription

let version = "1.24.0"
let checksum = "099ae1e045e254fbf803f98ff74607123bbd288c4f17725e19be5704b8039ef4"
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

