// swift-tools-version:5.5
import PackageDescription

// Version is technically not required here, SPM doesn't check
let version = "2.10.0"
// Tag is required to point towards the right asset. SPM requires the tag to follow semantic versioning to be able to resolve it.
let tag = "2.10.0"
let checksum = "1bb2ef0a974eabb745c80c24d758fac251db5fb15f37aca6f70a848753e91f62"
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
