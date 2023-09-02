// swift-tools-version:5.3
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "2.5.0-beta.2"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "2.5.0-beta.2"
let checksum = "8efa53590e1c49a2e12e472cf078ca4f263bc61c80412a8ea564939050d864ce"
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
