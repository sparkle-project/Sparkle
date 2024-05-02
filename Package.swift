// swift-tools-version:5.3
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "1.27.2"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "1.27.2"
let checksum = "7be019bef25f3224099a3f396a9fdb30b2d01561576f971d1d004d99b4716ed4"
let url = "https://github.com/sparkle-project/Sparkle/releases/download/\(tag)/Sparkle-for-Swift-Package-Manager.zip"

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

