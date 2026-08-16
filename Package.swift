// swift-tools-version:5.5
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "2.9.6"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "2.9.6"
let checksum = "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"
let url = "https://github.com/sparkle-project/Sparkle/releases/download/\(tag)/Sparkle-for-Swift-Package-Manager.zip"

let package = Package(
    name: "Sparkle",
    platforms: [.macOS(.v12)], // leaving "12.0" as a breadcrumb for searching; aligned with swift-tools-version at top of file (see https://developer.apple.com/documentation/packagedescription/supportedplatform/macosversion)
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
