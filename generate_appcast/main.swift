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
    static var programName: String = CommandLine.arguments.first ?? "./generate-appcast"
    
    @Option(name: .customShort("s"), help: ArgumentHelp("The private EdDSA string (128 characters).", valueName: "private-EdDSA-key"))
    var privateEdString : String?
    
    @Option(name: .customShort("f"), help: ArgumentHelp("Path to the private DSA key file.", valueName: "private-dsa-key-file"), transform: { URL(fileURLWithPath: $0) })
    var privateDSAKeyURL: URL?
    
    @Option(name: .customShort("n"), help: ArgumentHelp("The name of the private DSA key. This option must be used together with `-k`.", valueName: "dsa-key-name"))
    var privateDSAKeyName: String?
    
    @Option(name: .customShort("k"), help: ArgumentHelp("The path to the keychain to look up the private DSA key. This option must be used together with `-n`.", valueName: "keychain-for-dsa"), transform: { URL(fileURLWithPath: $0) })
    var keychainURL: URL?
    
    @Option(name: .customLong("download-url-prefix"), help: ArgumentHelp("A URL that will be used as prefix for the URL from where updates will be downloaded.", valueName: "url"), transform: { URL(string: $0) })
    var downloadURLPrefix : URL?
    
    @Option(name: .customLong("release-notes-url-prefix"), help: ArgumentHelp("A URL that will be used as prefix for constructing URLs for release notes.", valueName: "url"), transform: { URL(string: $0) })
    var releaseNotesURLPrefix : URL?
    
    @Option(name: .customShort("o"), help: ArgumentHelp("Path to filename for the generated appcast (allowed when only one will be created).", valueName: "output-path"), transform: { URL(fileURLWithPath: $0) })
    var outputPathURL: URL?
    
    @Argument(help: "The path to the directory containing the update archives and delta files.", transform: { URL(fileURLWithPath: $0, isDirectory: true) })
    var archivesSourceDir: URL
    
    @Flag(help: .hidden)
    var verbose: Bool = false
    
    static var configuration = CommandConfiguration(
        abstract: "Generate appcast from a directory of Sparkle update archives.",
        discussion: """
        Appcast files and deltas will be written to the archives directory.
        Note that pkg-based updates are not supported.
        
        EXAMPLES:
            \(programName) ./my-app-release-zipfiles/
            \(programName) -o appcast-name.xml ./my-app-release-zipfiles/
        """)
    
    func validate() throws {
        guard (keychainURL == nil) == (privateDSAKeyName == nil) else {
            throw ValidationError("Both -n <dsa-key-name> and -k <keychain> options must be provided together, or neither should be provided.")
        }
        
        // Both keychain/dsa key name options, and private dsa key file options cannot coexist
        guard (keychainURL == nil) || (privateDSAKeyURL == nil) else {
            throw ValidationError("-f <private-dsa-key-file> cannot be provided if -n <dsa-key-name> and -k <keychain> is provided")
        }
    }
    
    func run() throws {
        DispatchQueue.global().async(execute: {
            generateAppcast()
            CFRunLoopStop(CFRunLoopGetMain())
        })
        CFRunLoopRun()
    }
    
    func generateAppcast() {
        // Extract the keys
        let privateDSAKey : SecKey?
        if let privateDSAKeyURL = privateDSAKeyURL {
            do {
                privateDSAKey = try loadPrivateDSAKey(at: privateDSAKeyURL)
            } catch {
                print("Unable to load DSA private key from", privateDSAKeyURL.path, "\n", error)
                Darwin.exit(1)
            }
        } else if let keychainURL = keychainURL, let privateDSAKeyName = privateDSAKeyName {
            do {
                privateDSAKey = try loadPrivateDSAKey(named: privateDSAKeyName, fromKeychainAt: keychainURL)
            } catch {
                print("Unable to load DSA private key '\(privateDSAKeyName)' from keychain at", keychainURL.path, "\n", error)
                Darwin.exit(1)
            }
        } else {
            privateDSAKey = nil
        }
        
        let keys = loadPrivateKeys(privateDSAKey, privateEdString)
        
        do {
            let allUpdates = try makeAppcast(archivesSourceDir: archivesSourceDir, keys: keys, verbose: verbose)
            
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
                Darwin.exit(1)
            }
            
            for (appcastFile, updates) in allUpdates {
                // If an output filename was specified, use it.
                // Otherwise, use the name of the appcast file found in the archive.
                let appcastDestPath = outputPathURL ?? URL(fileURLWithPath: appcastFile,
                                                                relativeTo: archivesSourceDir)

                // Write the appcast
                try writeAppcast(appcastDestPath: appcastDestPath, updates: updates)

                // Inform the user, pluralizing "update" if necessary
                let updateString = (updates.count == 1) ? "update" : "updates"
                print("Wrote \(updates.count) \(updateString) to: \(appcastDestPath.path)")
            }
        } catch {
            print("Error generating appcast from directory", archivesSourceDir.path, "\n", error)
            Darwin.exit(1)
        }
    }
}

GenerateAppcast.main()
