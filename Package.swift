// swift-tools-version:5.3
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "1.27.1-rc.2"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "1.27.1-rc.2"
let checksum = "bad8b1adf12f0d1ab7ad093ca74727d6fafc2a3b2066e67e92bec3938ef0e0c1"
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

