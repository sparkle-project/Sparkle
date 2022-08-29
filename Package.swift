// swift-tools-version:5.3
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "2.2.2"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "2.2.2"
let checksum = "fe355fade2feeeb712bacd41079c4029cf4f465c54348a9b140fab395e45f79c"
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
