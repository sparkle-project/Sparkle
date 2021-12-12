// swift-tools-version:5.3
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "2.0.0-rc.1"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "2.0.0-rc.1"
let checksum = "437cdec8be612996d8072d2b03cf5c60d4d79335d8511c73b49e3c8a9a59618e"
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
