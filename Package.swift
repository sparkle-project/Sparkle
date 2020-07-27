// swift-tools-version:5.3
import PackageDescription

let defines: [CSetting] = [
    .define("SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME", to: "0"),
    .define("SPARKLE_AUTOMATED_DOWNGRADES", to: "0"),
    .define("SPARKLE_APPEND_VERSION_NUMBER", to: "1"),
    .define("SPARKLE_BUNDLE_IDENTIFIER", to: "\"org.sparkle-project.Sparkle\""),
    .define("SPARKLE_RELAUNCH_TOOL_NAME", to: "\"Autoupdate\""),
    .define("SPARKLE_FILEOP_TOOL_NAME", to: "\"fileop\"")
]

let package = Package(
    name: "Sparkle",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_11)],
    products: [
        .library(
            name: "Sparkle",
            targets: ["Sparkle"]),
        .library(name: "bsdiff", targets: ["bsdiff"]),
        .library(name: "ed25519", targets: ["ed25519"]),
        // These could be included with some effort, not required to build
        //        .executable(name: "generate_appcast", targets: ["generate_appcast"]),
        //        .executable(name: "sign_update", targets: ["sign_update"]),
        //        .executable(name: "generate_keys", targets: ["generate_keys"])
    ],
    targets: [
        // Main targets for Sparkle
        .target(
            name: "fileop",
            exclude: ["fileop.m"],
            publicHeadersPath: ".",
            cSettings: [.headerSearchPath("../Sparkle")] // For AppKitPrevention.h
        ),
        .target(
            name: "bsdiff",
            publicHeadersPath: "."
        ),
        .target(
            // A separate target with an include folder is required here so SwiftPM recognizes the correct headers
            // TODO: This should be the same source files for the xcodeproj
            name: "ed25519"
        ),
        .target(
            name: "Sparkle",
            dependencies: ["bsdiff", "ed25519", "fileop"],
            exclude: ["CheckLocalizations.swift", "Sparkle-Info.plist", "SUBinaryDeltaTool.m"],
            resources: [.process("DarkAqua.css")],
            cSettings: defines,
            linkerSettings: [.linkedLibrary("xar"), .linkedLibrary("bz2")]
        ),
        .testTarget(
            name: "SparkleUnitTestsObjC", // WARNING: The target name should not contain spaces or the resources can't be found
            dependencies: ["Sparkle"],
            path: "Tests/Sparkle Unit Tests",
            exclude: ["Swift", "SparkleTests-Info.plist"],
            resources: [.process("Resources")],
            cSettings: defines + [.headerSearchPath("../../Sources/Sparkle")]
        ),
        .testTarget(
            name: "SparkleUnitTestsSwift",
            dependencies: ["Sparkle"],
            path: "Tests/Sparkle Unit Tests",
            exclude: ["ObjC",
                      "SparkleTests-Info.plist"
            ],
            resources: [.process("Resources")],
            cSettings: [.headerSearchPath("../../Sources/Sparkle")],
            swiftSettings: [
                .unsafeFlags(["-import-objc-header",
                              "./Tests/Sparkle Unit Tests/Sparkle Unit Tests-Bridging-Header.h"])
            ]
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["Sparkle"],
            exclude: ["UITests-Info.plist"]
        ),
        
        // Executables
        //        .target(
        //            name: "generate_appcast",
        //            dependencies: ["Sparkle"]
        //        ),
        //        .target(
        //            name: "sign_update",
        //            dependencies: ["ed25519"]
        //        ),
        //        .target(
        //            name: "generate_keys",
        //            dependencies: ["ed25519"]
        //        )
    ]
)
