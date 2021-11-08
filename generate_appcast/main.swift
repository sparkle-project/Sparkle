//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation
import ArgumentParser

func loadPrivateKeys(_ privateDSAKey: SecKey?, _ privateEdString: String?) -> PrivateKeys {
    var privateEdKey: Data?
    var publicEdKey: Data?
    var item: CFTypeRef?
    var keys: Data?

    // private + public key is provided as argument
    if let privateEdString = privateEdString {
        if privateEdString.count == 128, let data = Data(base64Encoded: privateEdString) {
            keys = data
        } else {
            print("Warning: Private key not found in the argument. Please provide a valid key.")
        }
    }
    // get keys from kechain instead
    else {
        let res = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "https://sparkle-project.org",
            kSecAttrAccount as String: "ed25519",
            kSecAttrProtocol as String: kSecAttrProtocolSSH,
            kSecReturnData as String: kCFBooleanTrue!,
        ] as CFDictionary, &item)
        if res == errSecSuccess, let encoded = item as? Data, let data = Data(base64Encoded: encoded) {
            keys = data
        } else {
            print("Warning: Private key not found in the Keychain (\(res)). Please run the generate_keys tool")
        }
    }

    if let keys = keys {
        privateEdKey = keys[0..<64]
        publicEdKey = keys[64...]
    }
    return PrivateKeys(privateDSAKey: privateDSAKey, privateEdKey: privateEdKey, publicEdKey: publicEdKey)
}

struct GenerateAppcast: ParsableCommand {
    static let programName = "generate_appcast"
    static let programNamePath: String = CommandLine.arguments.first ?? "./\(programName)"
    static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Sparkle_generate_appcast")
    
    static let DEFAULT_MAX_NEW_VERSIONS_IN_FEED = 5
    static let DEFAULT_MAXIMUM_DELTAS = 5
    
    @Option(name: .customShort("s"), help: ArgumentHelp("The private EdDSA string (128 characters). If not specified, the private EdDSA key will be read from the Keychain instead.", valueName: "private-EdDSA-key"))
    var privateEdString : String?
    
    @Option(name: .customShort("f"), help: ArgumentHelp("Path to the private DSA key file. Only use this option for transitioning to EdDSA from older updates.", valueName: "private-dsa-key-file"), transform: { URL(fileURLWithPath: $0) })
    var privateDSAKeyURL: URL?
    
    @Option(name: .customShort("n"), help: ArgumentHelp("The name of the private DSA key. This option must be used together with `-k`. Only use this option for transitioning to EdDSA from older updates.", valueName: "dsa-key-name"))
    var privateDSAKeyName: String?
    
    @Option(name: .customShort("k"), help: ArgumentHelp("The path to the keychain to look up the private DSA key. This option must be used together with `-n`. Only use this option for transitioning to EdDSA from older updates.", valueName: "keychain-for-dsa"), transform: { URL(fileURLWithPath: $0) })
    var keychainURL: URL?
    
    @Option(name: .customLong("download-url-prefix"), help: ArgumentHelp("A URL that will be used as prefix for the URL from where updates will be downloaded.", valueName: "url"), transform: { URL(string: $0) })
    var downloadURLPrefix : URL?
    
    @Option(name: .customLong("release-notes-url-prefix"), help: ArgumentHelp("A URL that will be used as prefix for constructing URLs for release notes.", valueName: "url"), transform: { URL(string: $0) })
    var releaseNotesURLPrefix : URL?
    
    @Option(name: .customLong("full-release-notes-url"), help: ArgumentHelp("A URL that will be used for the full release notes.", valueName: "url"))
    var fullReleaseNotesURL: String?
    
    @Option(name: .long, help: ArgumentHelp("A URL to the application's website which Sparkle may use for directing users to if they cannot download a new update from within the application. This will be used for new generated update items. By default, no product link is used.", valueName: "link"))
    var link: String?
    
    @Option(name: .long, help: ArgumentHelp("An optional comma delimited list of application versions (specified by CFBundleVersion) to generate new update items for. By default, new update items are inferred from the available archives and are only generated if they are in the latest \(DEFAULT_MAX_NEW_VERSIONS_IN_FEED) updates in the appcast.", valueName: "versions"), transform: { Set($0.components(separatedBy: ",")) })
    var versions: Set<String>?
    
    @Option(name: .long, help: ArgumentHelp("The maximum number of delta items to create for the latest update for each minimum required operating system.", valueName: "maximum-deltas"))
    var maximumDeltas: Int = DEFAULT_MAXIMUM_DELTAS
    
    @Option(name: .long, help: ArgumentHelp("The Sparkle channel name that will be used for generating new updates. By default, no channel is used. Old applications need to be using Sparkle 2 to use this feature.", valueName: "channel-name"))
    var channel: String?
    
    @Option(name: .long, help: ArgumentHelp("The last major or minimum autoupdate sparkle:version that will be used for generating new updates. By default, no last major version is used.", valueName: "major-version"))
    var majorVersion: String?
    
    @Option(name: .long, help: ArgumentHelp("The phased rollout interval in seconds that will be used for generating new updates. By default, no phased rollout interval is used.", valueName: "phased-rollout-interval"), transform: { Int($0) })
    var phasedRolloutInterval: Int?
    
    @Option(name: .long, help: ArgumentHelp("The last critical update sparkle:version that will be used for generating new updates. An empty string argument will treat this update as critical coming from any application version. By default, no last critical update version is used. Old applications need to be using Sparkle 2 to use this feature.", valueName: "critical-update-version"))
    var criticalUpdateVersion: String?
    
    @Option(name: .long, help: ArgumentHelp("A comma delimited list of application sparkle:version's that will see newly generated updates as being informational only. An empty string argument will treat this update as informational coming from any application version. By default, updates are not informational only. --link must also be provided. Old applications need to be using Sparkle 2 to use this feature.", valueName: "informational-update-versions"), transform: { $0.components(separatedBy: ",").filter({$0.count > 0}) })
    var informationalUpdateVersions: [String]?
    
    @Option(name: .customShort("o"), help: ArgumentHelp("Path to filename for the generated appcast (allowed when only one will be created).", valueName: "output-path"), transform: { URL(fileURLWithPath: $0) })
    var outputPathURL: URL?
    
    @Argument(help: "The path to the directory containing the update archives and delta files.", transform: { URL(fileURLWithPath: $0, isDirectory: true) })
    var archivesSourceDir: URL
    
    // New update items are only generated if they are in the latest maxNewVersionsInFeed updates in the appcast
    // If the `versions` to generate is specified however, this counter has no effect.
    // Keep this option hidden from the user for now
    @Option(name: .long, help: .hidden)
    var maxNewVersionsInFeed: Int = DEFAULT_MAX_NEW_VERSIONS_IN_FEED
    
    @Flag(help: .hidden)
    var verbose: Bool = false
    
    static var configuration = CommandConfiguration(
        abstract: "Generate appcast from a directory of Sparkle update archives.",
        discussion: """
        Appcast files and deltas will be written to the archives directory.
        
        If an appcast file is already present in the archives directory, that file will be re-used and updated with new entries.
        Old entries in the appcast are kept intact. Otherwise, a new appcast file will be generated and written.
        
        .html files that have the same filename as an archive (except for the file extension) will be used for release notes for that item.
        If the contents of these files are short (< \(CDATA_HTML_FRAGMENT_THRESHOLD) characters) and do not include a DOCTYPE or body tags, they will be treated as embedded CDATA release notes.
        
        For new update entries, Sparkle infers the minimum system OS requirement based on your update's LSMinimumSystemVersion provided
        by your application's Info.plist. If none is found, \(programName) defaults to Sparkle's own minimum system requirement (macOS 10.11).
        
        An example of an archives directory may look like:
            ./my-app-release-zipfiles/
                MyApp 1.0.zip
                MyApp 1.0.html
                MyApp 1.1.zip
                MyApp 1.1.html
                appcast.xml
                
        EXAMPLES:
            \(programNamePath) ./my-app-release-zipfiles/
            \(programNamePath) -o appcast-name.xml ./my-app-release-zipfiles/
        
        For more advanced options that can be used for publishing updates, see https://sparkle-project.org/documentation/publishing/ for further documentation.
        
        Extracted archives are cached in \((cacheDirectory.path as NSString).abbreviatingWithTildeInPath) to avoid re-computation in subsequent runs.
        
        Note that \(programName) does not support package-based (.pkg) updates.
        """)
    
    func validate() throws {
        guard (keychainURL == nil) == (privateDSAKeyName == nil) else {
            throw ValidationError("Both -n <dsa-key-name> and -k <keychain> options must be provided together, or neither should be provided.")
        }
        
        // Both keychain/dsa key name options, and private dsa key file options cannot coexist
        guard (keychainURL == nil) || (privateDSAKeyURL == nil) else {
            throw ValidationError("-f <private-dsa-key-file> cannot be provided if -n <dsa-key-name> and -k <keychain> is provided")
        }
        
        if let versions = versions {
            guard versions.count > 0 else {
                throw ValidationError("--versions must specify at least one application version.")
            }
        }
        
        guard (informationalUpdateVersions == nil) || (link != nil) else {
            throw ValidationError("--link must be specified if --informational-update-versions is specified.")
        }
    }
    
    func run() throws {
        // Extract the keys
        let privateDSAKey : SecKey?
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
        
        let keys = loadPrivateKeys(privateDSAKey, privateEdString)
        
        do {
            let allUpdates = try makeAppcast(archivesSourceDir: archivesSourceDir, cacheDirectory: GenerateAppcast.cacheDirectory, keys: keys, versions: versions, maximumDeltas: maximumDeltas, verbose: verbose)
            
            // If a URL prefix was provided, set on the archive items
            if downloadURLPrefix != nil || releaseNotesURLPrefix != nil {
                for (_, archiveItems) in allUpdates {
                    for archiveItem in archiveItems {
                        if let downloadURLPrefix = downloadURLPrefix {
                            archiveItem.downloadUrlPrefix = downloadURLPrefix
                        }
                        if let releaseNotesURLPrefix = releaseNotesURLPrefix {
                            archiveItem.releaseNotesURLPrefix = releaseNotesURLPrefix
                        }
                    }
                }
            }
            
            // If a (single) output filename was specified on the command-line, but more than one
            // appcast file was found in the archives, then it's an error.
            if let outputPathURL = outputPathURL,
                allUpdates.count > 1 {
                print("Cannot write to \(outputPathURL.path): multiple appcasts found")
                throw ExitCode(1)
            }
            
            for (appcastFile, updates) in allUpdates {
                // If an output filename was specified, use it.
                // Otherwise, use the name of the appcast file found in the archive.
                let appcastDestPath = outputPathURL ?? URL(fileURLWithPath: appcastFile,
                                                                relativeTo: archivesSourceDir)

                // Write the appcast
                let (numNewUpdates, numExistingUpdates) = try writeAppcast(appcastDestPath: appcastDestPath, updates: updates, newVersions: versions, maxNewVersionsInFeed: maxNewVersionsInFeed, fullReleaseNotesLink: fullReleaseNotesURL, link: link, newChannel: channel, majorVersion: majorVersion, phasedRolloutInterval: phasedRolloutInterval, criticalUpdateVersion: criticalUpdateVersion, informationalUpdateVersions: informationalUpdateVersions)

                // Inform the user, pluralizing "update" if necessary
                let pluralizeUpdates = { $0 == 1 ? "update" : "updates" }
                let newUpdatesString = pluralizeUpdates(numNewUpdates)
                let existingUpdatesString = pluralizeUpdates(numExistingUpdates)
                
                print("Wrote \(numNewUpdates) new \(newUpdatesString) and updated \(numExistingUpdates) existing \(existingUpdatesString)")
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
