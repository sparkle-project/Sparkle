// swift-tools-version:5.5
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "2.10.0-beta.1"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "2.10.0-beta.1"
let checksum = "a5dfcf2366208e368d8258306ba5ce4d267b030226098a1e14ec4b8abb3fb890"
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
