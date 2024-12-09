//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation
import ArgumentParser

func loadPrivateKeys(_ account: String, _ privateDSAKey: SecKey?, _ privateEdString: String?, allowNewPrivateKey: Bool) -> PrivateKeys? {
    var privateEdKey: Data?
    var publicEdKey: Data?
    var item: CFTypeRef?
    var secret: Data?

    // private + public key is provided as argument (for older format)
    if let privateEdString {
        if let data = Data(base64Encoded: privateEdString) {
            if allowNewPrivateKey || secretUsesOldHashedSeed(secret: data) {
                // We always allow the old format without private seed
                secret = data
            } else if !allowNewPrivateKey && secretUsesRegularSeed(secret: data) {
                // Don't support deprecated option for newly generated keys
                print("Error: specifying private key as the argument is no longer supported.")
                return nil
            } else {
                print("Error: Private key not decoded from the argument, which has \(data.count) bytes. Please provide a valid key and confirm the contents of the key are correct.")
                return nil
            }
        } else {
            print("Error: Private key not decoded from the argument because it isn't base64 encoded. Please provide a valid key and confirm the contents of the key are correct.")
            return nil
        }
    }
    // get keys from kechain instead
    else {
        let res = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "https://sparkle-project.org",
            kSecAttrAccount as String: account,
            kSecAttrProtocol as String: kSecAttrProtocolSSH,
            kSecReturnData as String: kCFBooleanTrue!,
        ] as CFDictionary, &item)
        if res == errSecSuccess, let encoded = item as? Data {
            if let data = Data(base64Encoded: encoded) {
                secret = data
            } else {
                print("Error: Failed to base64 decode secret data from keychain")
                return nil
            }
        } else {
            print("Warning: Private key for account \(account) not found in the Keychain (\(res)). Please run the generate_keys tool")
        }
    }

    if let secret {
        guard let (privateKey, publicKey) = decodePrivateAndPublicKeys(secret: secret) else {
            print("Error: Failed to decode private and public keys from secret data")
            return nil
        }
        privateEdKey = privateKey
        publicEdKey = publicKey
    }
    return PrivateKeys(privateDSAKey: privateDSAKey, privateEdKey: privateEdKey, publicEdKey: publicEdKey)
}

let DEFAULT_MAX_CDATA_THRESHOLD = 1000

struct GenerateAppcast: ParsableCommand {
    static let programName = "generate_appcast"
    static let programNamePath: String = CommandLine.arguments.first ?? "./\(programName)"
    static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Sparkle_generate_appcast")
    static let oldFilesDirectoryName = "old_updates"
    
    static let DEFAULT_MAX_VERSIONS_PER_BRANCH_IN_FEED = 3
    static let DEFAULT_MAXIMUM_DELTAS = 5
    
    @Option(help: ArgumentHelp("The account name in your keychain associated with your private EdDSA (ed25519) key to use for signing new updates."))
    var account : String = "ed25519"
    
    @Option(name: .customLong("ed-key-file"), help: ArgumentHelp("Path to the private EdDSA key file. If not specified, the private EdDSA key will be read from the Keychain instead. '-' can be used to echo the EdDSA key from a 'secret' environment variable to the standard input stream. For example: echo \"$PRIVATE_KEY_SECRET\" | ./\(programName) --ed-key-file -", valueName: "private-EdDSA-key-file"))
    var privateEdKeyPath: String?
    
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
    @Option(name: .customShort("f"), help: ArgumentHelp("Path to the private DSA key file. Only use this option for transitioning to EdDSA from older updates.", valueName: "private-dsa-key-file"), transform: { URL(fileURLWithPath: $0) })
    var privateDSAKeyURL: URL?
    
    @Option(name: .customShort("n"), help: ArgumentHelp("The name of the private DSA key. This option must be used together with `-k`. Only use this option for transitioning to EdDSA from older updates.", valueName: "dsa-key-name"))
    var privateDSAKeyName: String?
#endif
    
    @Option(name: .customShort("s"), help: ArgumentHelp("(DEPRECATED): The private EdDSA string (128 characters). This option is deprecated. Please use the Keychain, or pass the key as standard input when using the --ed-key-file - option instead. This option is no longer supported for newly generated keys.", valueName: "private-EdDSA-key"))
    var privateEdString : String?
    
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
    @Option(name: .customShort("k"), help: ArgumentHelp("The path to the keychain to look up the private DSA key. This option must be used together with `-n`. Only use this option for transitioning to EdDSA from older updates.", valueName: "keychain-for-dsa"), transform: { URL(fileURLWithPath: $0) })
    var keychainURL: URL?
#endif
    
    @Option(name: .customLong("download-url-prefix"), help: ArgumentHelp("A URL that will be used as prefix for the URL from where updates will be downloaded.", valueName: "url"), transform: { URL(string: $0) })
    var downloadURLPrefix : URL?
    
    @Option(name: .customLong("release-notes-url-prefix"), help: ArgumentHelp("A URL that will be used as prefix for constructing URLs for release notes.", valueName: "url"), transform: { URL(string: $0) })
    var releaseNotesURLPrefix : URL?
    
    @Flag(name: .customLong("embed-release-notes"), help: ArgumentHelp("Embed release notes in a new update's description. By default, release note files are only embedded if they are HTML and do not include DOCTYPE or body tags. This flag forces release note files for newly created updates to always be embedded."))
    var embedReleaseNotes : Bool = false
    
    @Option(name: .customLong("full-release-notes-url"), help: ArgumentHelp("A URL that will be used for the full release notes.", valueName: "url"))
    var fullReleaseNotesURL: String?
    
    @Option(name: .long, help: ArgumentHelp("A URL to the application's website which Sparkle may use for directing users to if they cannot download a new update from within the application. This will be used for new generated update items. By default, no product link is used.", valueName: "link"))
    var link: String?
    
    @Option(name: .long, help: ArgumentHelp("An optional comma delimited list of application versions (specified by CFBundleVersion) to generate new update items for. By default, new update items are inferred from the available archives and current feed. Use this option if you need to insert only a specific new version or insert an old update in the feed at a different branch point (e.g. with a different minimum OS version or channel).", valueName: "versions"), transform: { Set($0.components(separatedBy: ",")) })
    var versions: Set<String>?
    
    @Option(name: .customLong("maximum-versions"), help: ArgumentHelp("The maximum number of versions to preserve in the generated appcast for each branch point (e.g. with a different minimum OS requirement). If this value is 0, then all items in the appcast are preserved.", valueName: "maximum-versions"), transform: { value -> Int in
        if let intValue = Int(value) {
            return (intValue <= 0) ? Int.max : intValue
        } else {
            return DEFAULT_MAX_VERSIONS_PER_BRANCH_IN_FEED
        }
    })
    var maxVersionsPerBranchInFeed: Int = DEFAULT_MAX_VERSIONS_PER_BRANCH_IN_FEED
    
    @Option(name: .long, help: ArgumentHelp("The maximum number of delta items to create for the latest update for each branch point (e.g. with a different minimum OS requirement).", valueName: "maximum-deltas"))
    var maximumDeltas: Int = DEFAULT_MAXIMUM_DELTAS
    
    @Option(name: .long, help: ArgumentHelp(COMPRESSION_METHOD_ARGUMENT_DESCRIPTION, valueName: "delta-compression"))
    var deltaCompression: String = "default"
    
    @Option(name: .long, help: .hidden)
    var deltaCompressionLevel: UInt8 = 0
    
    @Option(name: .long, help: ArgumentHelp("The Sparkle channel name that will be used for generating new updates. By default, no channel is used. Old applications need to be using Sparkle 2 to use this feature.", valueName: "channel-name"))
    var channel: String?
    
    @Option(name: .long, help: ArgumentHelp("The last major or minimum autoupdate sparkle:version that will be used for generating new updates. By default, no last major version is used.", valueName: "major-version"))
    var majorVersion: String?
    
    @Option(name: .long, help: ArgumentHelp("Ignore skipped major upgrades below this specified version. Only applicable for major upgrades.", valueName: "below-version"))
    var ignoreSkippedUpgradesBelowVersion: String?
    
    @Option(name: .long, help: ArgumentHelp("The phased rollout interval in seconds that will be used for generating new updates. By default, no phased rollout interval is used.", valueName: "phased-rollout-interval"), transform: { Int($0) })
    var phasedRolloutInterval: Int?
    
    @Option(name: .long, help: ArgumentHelp("The last critical update sparkle:version that will be used for generating new updates. An empty string argument will treat this update as critical coming from any application version. By default, no last critical update version is used. Old applications need to be using Sparkle 2 to use this feature.", valueName: "critical-update-version"))
    var criticalUpdateVersion: String?
    
    @Option(name: .long, help: ArgumentHelp("A comma delimited list of application sparkle:version's that will see newly generated updates as being informational only. An empty string argument will treat this update as informational coming from any application version. Prefix a version string with '<' to indicate (eg \"<2.5\") to indicate older versions than the one specified should treat the update as informational only. By default, updates are not informational only. --link must also be provided. Old applications need to be using Sparkle 2 to use this feature, and 2.1 or later to use the '<' upper bound feature.", valueName: "informational-update-versions"), transform: { $0.components(separatedBy: ",").filter({$0.count > 0}) })
    var informationalUpdateVersions: [String]?
    
    @Flag(name: .customLong("auto-prune-update-files"), help: ArgumentHelp("Automatically remove old update files in \(oldFilesDirectoryName) that haven't been touched in 2 weeks"))
    var autoPruneUpdates: Bool = false
    
    @Option(name: .customShort("o"), help: ArgumentHelp("Path to filename for the generated appcast (allowed when only one will be created).", valueName: "output-path"), transform: { URL(fileURLWithPath: $0) })
    var outputPathURL: URL?
    
    @Argument(help: "The path to the directory containing the update archives and delta files.", transform: { URL(fileURLWithPath: $0, isDirectory: true) })
    var archivesSourceDir: URL
    
    @Flag(help: .hidden)
    var verbose: Bool = false
    
    @Flag(name: .customLong("disable-nested-code-check"), help: .hidden)
    var disableNestedCodeCheck: Bool = false
    
    static var configuration = CommandConfiguration(
        abstract: "Generate appcast from a directory of Sparkle update archives.",
        discussion: """
        Appcast files and deltas will be written to the archives directory.
        
        If an appcast file is already present in the archives directory, that file will be re-used and updated with new entries.
        Otherwise, a new appcast file will be generated and written.
        
        Old updates are automatically removed from the generated appcast feed and their update files are moved to \(oldFilesDirectoryName)/
        If --auto-prune-update-files is passed, old update files in this directory are deleted after 2 weeks.
        You may want to exclude files from this directory from being uploaded.
        
        Use the --versions option if you need to insert an update that is older than the latest update in your feed, or
        if you need to insert only a specific new version with certain parameters.
        
        .html or .txt files that have the same filename as an archive (except for the file extension) will be used for release notes for that item.
        For HTML release notes, if the contents of these files do not include a DOCTYPE or body tags, they will be treated as embedded CDATA release notes.
        Release notes for new items can be forced to be embedded by passing --embed-release-notes
        
        For new update entries, Sparkle infers the minimum system OS requirement based on your update's LSMinimumSystemVersion provided
        by your application's Info.plist. If none is found, \(programName) defaults to Sparkle's own minimum system requirement (macOS 10.13).
        
        An example of an archives directory may look like:
            ./my-app-release-zipfiles/
                MyApp 1.0.zip
                MyApp 1.0.html
                MyApp 1.1.zip
                MyApp 1.1.html
                appcast.xml
                \(oldFilesDirectoryName)/
                
        EXAMPLES:
            \(programNamePath) ./my-app-release-zipfiles/
            \(programNamePath) -o appcast-name.xml ./my-app-release-zipfiles/
        
        For more advanced options that can be used for publishing updates, see https://sparkle-project.org/documentation/publishing/ for further documentation.
        
        Extracted archives that are needed are cached in \((cacheDirectory.path as NSString).abbreviatingWithTildeInPath) to avoid re-computation in subsequent runs.
                
        Note that \(programName) does not support package-based (.pkg) updates.
        """)
    
    func validate() throws {
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
        guard (keychainURL == nil) == (privateDSAKeyName == nil) else {
            throw ValidationError("Both -n <dsa-key-name> and -k <keychain> options must be provided together, or neither should be provided.")
        }
        
        // Both keychain/dsa key name options, and private dsa key file options cannot coexist
        guard (keychainURL == nil) || (privateDSAKeyURL == nil) else {
            throw ValidationError("-f <private-dsa-key-file> cannot be provided if -n <dsa-key-name> and -k <keychain> is provided")
        }
#endif
        
        guard (privateEdKeyPath == nil) || (privateEdString == nil) else {
            throw ValidationError("--ed-key-file <private-EdDSA-key-file> cannot be provided if -s <private-EdDSA-key> is provided")
        }
        
        if let versions = versions {
            guard versions.count > 0 else {
                throw ValidationError("--versions must specify at least one application version.")
            }
        }
        
        guard (informationalUpdateVersions == nil) || (link != nil) else {
            throw ValidationError("--link must be specified if --informational-update-versions is specified.")
        }
        
        guard deltaCompressionLevel >= 0 && deltaCompressionLevel <= 9 else {
            throw ValidationError("Invalid --delta-compression-level value was passed.")
        }
        
        var validCompression: ObjCBool = false
        let _ = deltaCompressionModeFromDescription(deltaCompression, &validCompression)
        if !validCompression.boolValue {
            throw ValidationError("Invalid --delta-compression \(deltaCompression) was passed.")
        }
    }
    
    func run() throws {
        // Ignore SIGPIPE because we won't want read or write failures due to broken pipe to unexpectably
        // terminate the process, when extracting archives
        signal(SIGPIPE, SIG_IGN)
        
        // Extract the keys
        let privateDSAKey : SecKey?
    #if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
        if let privateDSAKeyURL = privateDSAKeyURL {
            do {
                privateDSAKey = try loadPrivateDSAKey(at: privateDSAKeyURL)
            } catch {
                print("Unable to load DSA private key from", privateDSAKeyURL.path, "\n", error)
                throw ExitCode(1)
            }
        } else if let keychainURL = keychainURL, let privateDSAKeyName = privateDSAKeyName {
            do {
                privateDSAKey = try loadPrivateDSAKey(named: privateDSAKeyName, fromKeychainAt: keychainURL)
            } catch {
                print("Unable to load DSA private key '\(privateDSAKeyName)' from keychain at", keychainURL.path, "\n", error)
                throw ExitCode(1)
            }
        } else {
            privateDSAKey = nil
        }
    #else
        privateDSAKey = nil
    #endif
        
        let allowNewPrivateKey: Bool
        let privateEdKeyString: String?
        if let privateEdString = privateEdString {
            privateEdKeyString = privateEdString
            
            print("Warning: The -s option for passing the private EdDSA key is insecure and deprecated. Please see its help usage for more information.")
            allowNewPrivateKey = false
        } else if let privateEdKeyPath = privateEdKeyPath {
            do {
                if privateEdKeyPath == "-" && !FileManager.default.fileExists(atPath: privateEdKeyPath) {
                    if let line = readLine(strippingNewline: true) {
                        privateEdKeyString = line
                    } else {
                        print("Unable to read EdDSA private key from standard input")
                        throw ExitCode(1)
                    }
                } else {
                    do {
                        privateEdKeyString = try decodeSecretString(filePath: privateEdKeyPath)
                    } catch {
                        print(error.localizedDescription)
                        throw ExitCode(1)
                    }
                }
                
                allowNewPrivateKey = true
            } catch {
                print("Unable to load EdDSA private key from", privateEdKeyPath, "\n", error)
                throw ExitCode(1)
            }
        } else {
            privateEdKeyString = nil
            allowNewPrivateKey = true
        }
        
        guard let keys = loadPrivateKeys(account, privateDSAKey, privateEdKeyString, allowNewPrivateKey: allowNewPrivateKey) else {
            throw ExitCode(1)
        }
        
        do {
            let appcastsByFeed = try makeAppcasts(archivesSourceDir: archivesSourceDir, outputPathURL: outputPathURL, cacheDirectory: GenerateAppcast.cacheDirectory, keys: keys, versions: versions, maxVersionsPerBranchInFeed: maxVersionsPerBranchInFeed, newChannel: channel, majorVersion: majorVersion, maximumDeltas: maximumDeltas, deltaCompressionModeDescription: deltaCompression, deltaCompressionLevel: deltaCompressionLevel, disableNestedCodeCheck: disableNestedCodeCheck, downloadURLPrefix: downloadURLPrefix, releaseNotesURLPrefix: releaseNotesURLPrefix, verbose: verbose)
            
            let oldFilesDirectory = archivesSourceDir.appendingPathComponent(GenerateAppcast.oldFilesDirectoryName)
            
            let pluralizeWord = { $0 == 1 ? $1 : "\($1)s" }
            
            for (appcastFile, appcast) in appcastsByFeed {
                // If an output filename was specified, use it.
                // Otherwise, use the name of the appcast file found in the archive.
                let appcastDestPath = outputPathURL ?? URL(fileURLWithPath: appcastFile,
                                                                relativeTo: archivesSourceDir)

                // Write the appcast
                let (numNewUpdates, numExistingUpdates, numUpdatesRemoved) = try writeAppcast(appcastDestPath: appcastDestPath, appcast: appcast, fullReleaseNotesLink: fullReleaseNotesURL, preferToEmbedReleaseNotes: embedReleaseNotes, link: link, newChannel: channel, majorVersion: majorVersion, ignoreSkippedUpgradesBelowVersion: ignoreSkippedUpgradesBelowVersion, phasedRolloutInterval: phasedRolloutInterval, criticalUpdateVersion: criticalUpdateVersion, informationalUpdateVersions: informationalUpdateVersions)

                // Inform the user, pluralizing "update" if necessary
                let pluralizeUpdates = { pluralizeWord($0, "update") }
                let newUpdatesString = pluralizeUpdates(numNewUpdates)
                let existingUpdatesString = pluralizeUpdates(numExistingUpdates)
                let removedUpdatesString = pluralizeUpdates(numUpdatesRemoved)
                
                print("Wrote \(numNewUpdates) new \(newUpdatesString), updated \(numExistingUpdates) existing \(existingUpdatesString), and removed \(numUpdatesRemoved) old \(removedUpdatesString) in \(appcastFile)")
            }
            
            let (moveCount, prunedCount) = moveOldUpdatesFromAppcasts(archivesSourceDir: archivesSourceDir, oldFilesDirectory: oldFilesDirectory, cacheDirectory: GenerateAppcast.cacheDirectory, appcasts: Array(appcastsByFeed.values), autoPruneUpdates: autoPruneUpdates)
            if moveCount > 0 {
                print("Moved \(moveCount) old update \(pluralizeWord(moveCount, "file")) to \(oldFilesDirectory.lastPathComponent)")
            }
            if prunedCount > 0 {
                print("Pruned \(prunedCount) old update \(pluralizeWord(prunedCount, "file"))")
            }
        } catch {
            print("Error generating appcast from directory", archivesSourceDir.path, "\n", error)
            throw ExitCode(1)
        }
    }
}

DispatchQueue.global().async(execute: {
    GenerateAppcast.main()
    CFRunLoopStop(CFRunLoopGetMain())
})
CFRunLoopRun()
