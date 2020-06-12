//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation
import ArgumentParser

struct GenerateAppcast: ParsableCommand {
    static var commandName = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
    static var configuration: CommandConfiguration = {
        return CommandConfiguration(commandName: commandName, abstract: "Generate appcast from a directory of Sparkle update archives", discussion: """
            Appcast files and deltas will be written to the archives directory.
            Note that pkg-based updates are not supported.
            """)
    }()

    @Option(name: .customShort("f"), help: ArgumentHelp("The path to the private DSA key.", valueName: "dsa key"), transform: { URL(fileURLWithPath: $0) })
    var privateDSAKeyURL: URL?

    @Option(name: .customShort("n"), help: ArgumentHelp("The name of the private DSA key. This option must be used together with `-k`.", valueName: "dsa key name"))
    var privateDSAKeyName: String?

    @Option(name: .customShort("k"), help: ArgumentHelp("The path to the keychain. This option must be used together with `-n`.", valueName: "keychain"), transform: { URL(fileURLWithPath: $0) })
    var keychainURL: URL?

    @Option(name: .customShort("s"), help: ArgumentHelp("The path to the private EdDSA key.", valueName: "eddsa key"))
    var privateEdDSAKey: String?

    @Option(help: ArgumentHelp("A static url that will be used as prefix for the url from where updates will be downloaded.", valueName: "url"), transform: { URL(string: $0) })
    var downloadURLPrefix: URL?

    @Argument(help: ArgumentHelp(
        """
        The path to the update directory
        e.g. \(commandName) ./my-app-release-zipfiles/
        OR for old apps that have DSA keys (deprecated):
            <private dsa key path> <directory with update files>
        e.g. \(commandName) dsa_priv.pem archives/
        """,
        valueName: "archives folder"),
              transform: { URL(fileURLWithPath: $0) })
    var updatesURLOrDSAKey: URL

    @Argument(help: .hidden, transform: { URL(fileURLWithPath: $0) })
    var legacyUpdatesURL: URL?

    @Flag(help: .hidden)
    var verbose: Bool

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
        } else { // get keys from kechain instead
            let res = SecItemCopyMatching([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "https://sparkle-project.org",
                kSecAttrAccount as String: "ed25519",
                kSecAttrProtocol as String: kSecAttrProtocolSSH,
                kSecReturnData as String: true,
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

    /**
     * Parses all possible command line options and returns the values in a tuple.
     */
    func parseCommandLineOptions() throws -> (privateDSAKey: SecKey?, privateEdString: String?, downloadUrlPrefix: URL?, archivesSourceDir: URL) {

        // define the variables for the possible argument values
        var privateDSAKey: SecKey?
        var privateEdString: String?
        var downloadUrlPrefix: URL?
        var archivesSourceDir: URL

        // check if the private dsa key option is present
        if let privateKeyUrl = privateDSAKeyURL {
            do {
                privateDSAKey = try loadPrivateDSAKey(at: privateKeyUrl)
            } catch {
                print("Unable to load DSA private key from", privateKeyUrl.path, "\n", error)
                throw ExitCode(1)
            }
        }

        // check if the private dsa sould be loaded using the keyname and the name of the keychain
        if let privateDSAKeyName = privateDSAKeyName, let keychainUrl = keychainURL {
            do {
                privateDSAKey = try loadPrivateDSAKey(named: privateDSAKeyName, fromKeychainAt: keychainUrl)
            } catch {
                print("Unable to load DSA private key '\(privateDSAKeyName)' from keychain at", keychainUrl.path, "\n", error)
                throw ExitCode(1)
            }
        }

        // check if the private EdDSA key string was given as an argument
        if let privateEdDSAKey = privateEdDSAKey {
            privateEdString = privateEdDSAKey
        }

        // check if a prefix for the download url of the archives was given
        downloadUrlPrefix = downloadURLPrefix

        // deal with the remaining arguments

        if legacyUpdatesURL != nil {
            // if there are two arguments left they are the private DSA key and the path to the archives directory (in this order)
            // first get the private DSA key
            do {
                privateDSAKey = try loadPrivateDSAKey(at: updatesURLOrDSAKey)
            } catch {
                print("Unable to load DSA private key from", updatesURLOrDSAKey.path, "\n", error)
                throw ExitCode(1)
            }
        }

        // now only the archives source dir is left
        archivesSourceDir = legacyUpdatesURL ?? updatesURLOrDSAKey

        return (privateDSAKey, privateEdString, downloadUrlPrefix, archivesSourceDir)
    }

    func run() throws {
        let (privateDSAKey, privateEdString, downloadUrlPrefix, archivesSourceDir) = try parseCommandLineOptions()

        let keys = loadPrivateKeys(privateDSAKey, privateEdString)

        do {
            let allUpdates = try makeAppcast(archivesSourceDir: archivesSourceDir, keys: keys, verbose: verbose)

            // if a download url prefix was provided set it for each archive item
            if downloadUrlPrefix != nil {
                for (_, archiveItems) in allUpdates {
                    for archiveItem in archiveItems {
                        archiveItem.downloadUrlPrefix = downloadUrlPrefix
                    }
                }
            }

            for (appcastFile, updates) in allUpdates {
                let appcastDestPath = URL(fileURLWithPath: appcastFile, relativeTo: archivesSourceDir)
                try writeAppcast(appcastDestPath: appcastDestPath, updates: updates)
                print("Written", appcastDestPath.path, "based on", updates.count, "updates")
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

