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
    static var configuration = CommandConfiguration(commandName: "generate_appcast", abstract: "Generate appcast from a directory of Sparkle update archives", discussion: """
            Appcast files and deltas will be written to the archives directory.
            Note that pkg-based updates are not supported.
            """)

    @Option(name: .customShort("f"), help: ArgumentHelp("provide the path to the private DSA key", valueName: "path"))
    var privateDSAKeyPath: String?

    @Option(name: .customShort("n"), help: ArgumentHelp("provide the name of the private DSA key. This option has to be used together with `-k`", valueName: "name"))
    var privateDSAKeyName: String?

    @Option(name: .customShort("k"), help: ArgumentHelp("provide the path to the keychain. This option has to be used together with `-n`", valueName: "path"))
    var keychainPath: String?

    @Option(name: .customShort("s"), help: ArgumentHelp("provide the path to the private EdDSA key", valueName: "path"))
    var privateEdDSAKeyPath: String?

    @Option(help: ArgumentHelp("provide a static url that will be used as prefix for the url from where updates will be downloaded", valueName: "url"))
    var downloadURLPrefix: String?

    @Argument(help: ArgumentHelp(
        """
        The path to the update directory
        OR for old apps that have DSA keys (deprecated):
            <private dsa key path> <directory with update files>
        e.g., \(Self.configuration.commandName!) dsa_priv.pem archives/
        """,
        valueName: "paths"))
    var restOfArgs: [String]

    var verbose = false

//    func printUsage() {
//        let command = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
//        print("Generate appcast from a directory of Sparkle update archives\n",
//              "Usage:\n",
//              "      \(command) <directory with update files>\n",
//            " e.g. \(command) ./my-app-release-zipfiles/\n",
//            "\nOR for old apps that have a DSA keys (deprecated):\n",
//            "      \(command) <private DSA key path> <directory with update files>\n",
//            " e.g. \(command) dsa_priv.pem archives/\n",
//            "\n",
//            "Appcast files and deltas will be written to the archives directory.\n",
//            "Note that pkg-based updates are not supported.\n"
//        )
//    }
//
//    func printHelp() {
//        let command = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
//        print(
//            "Usage: \(command) [OPTIONS] [ARCHIVES_FOLDER]\n",
//            "Options:\n",
//            "\t-f: provide the path to the private DSA key\n",
//            "\t-n: provide the name of the private DSA key. This option has to be used together with `-k`\n",
//            "\t-k: provide the name of the keychain. This option has to be used together with `-n`\n",
//            "\t-s: provide the path to the private EdDSA key\n",
//            "\t--download-url-prefix: provide a static url that will be used as prefix for the url from where updates will be downloaded\n"
//        )
//    }


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
                kSecReturnData as String: kCFBooleanTrue,
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
        if let privateDSAKeyPath = privateDSAKeyPath {
            // get the private DSA key
            let privateKeyUrl = URL(fileURLWithPath: privateDSAKeyPath)
            do {
                privateDSAKey = try loadPrivateDSAKey(at: privateKeyUrl)
            } catch {
                print("Unable to load DSA private key from", privateKeyUrl.path, "\n", error)
                throw ExitCode(1)
            }
        }

        // check if the private dsa sould be loaded using the keyname and the name of the keychain
        if let privateDSAKeyName = privateDSAKeyName, let keychainPath = keychainPath {
            // get the keyname and the keychain url to load the private DSA key
            let keychainUrl: URL = URL(fileURLWithPath: keychainPath)
            do {
                privateDSAKey = try loadPrivateDSAKey(named: privateDSAKeyName, fromKeychainAt: keychainUrl)
            } catch {
                print("Unable to load DSA private key '\(privateDSAKeyName)' from keychain at", keychainUrl.path, "\n", error)
                throw ExitCode(1)
            }
        }

        // check if the private EdDSA key string was given as an argument
        if let privateEdDSAKeyPath = privateEdDSAKeyPath {
            privateEdString = privateEdDSAKeyPath
        }

        // check if a prefix for the download url of the archives was given
        if let downloadURLPrefix = downloadURLPrefix {
            downloadUrlPrefix = URL(string: downloadURLPrefix)
        }

        // now that all command line options have been removed from the arguments array
        // there should only be the path to the private DSA key (if provided) path to the archives dir left
        var args = restOfArgs

        if args.count == 2 {
            // if there are two arguments left they are the private DSA key and the path to the archives directory (in this order)
            // first get the private DSA key
            let privateKeyUrl = URL(fileURLWithPath: restOfArgs[0])
            do {
                privateDSAKey = try loadPrivateDSAKey(at: privateKeyUrl)
            } catch {
                print("Unable to load DSA private key from", privateKeyUrl.path, "\n", error)
                throw ExitCode(1)
            }

            // remove the parsed path to the DSA key
            args.removeFirst()
        }

        // now only the archives source dir is left
        archivesSourceDir = URL(fileURLWithPath: args[0], isDirectory: true)

        return (privateDSAKey, privateEdString, downloadUrlPrefix, archivesSourceDir)
    }

    func run() throws {
        var privateDSAKey: SecKey?
        var privateEdString: String?
        var downloadUrlPrefix: URL?
        var archivesSourceDir: URL

        (privateDSAKey, privateEdString, downloadUrlPrefix, archivesSourceDir) = try parseCommandLineOptions()

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

//    DispatchQueue.global().async(execute: {
//    main()
//    CFRunLoopStop(CFRunLoopGetMain())
//    })
//
//    CFRunLoopRun()
}

GenerateAppcast.main()
