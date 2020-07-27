//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

var verbose = false

func printUsage() {
    let command = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
    print("Generate appcast from a directory of Sparkle update archives\n",
        "Usage:\n",
        "      \(command) <directory with update files>\n",
        " e.g. \(command) ./my-app-release-zipfiles/\n",
        "\nOR for old apps that have a DSA keys (deprecated):\n",
        "      \(command) <private DSA key path> <directory with update files>\n",
        " e.g. \(command) dsa_priv.pem archives/\n",
        "\n",
        "Appcast files and deltas will be written to the archives directory.\n",
        "Note that pkg-based updates are not supported.\n"
    )
}

func printHelp() {
    let command = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
    print(
        "Usage: \(command) [OPTIONS] [ARCHIVES_FOLDER]\n",
        "Options:\n",
        "\t-f: provide the path to the private DSA key\n",
        "\t-n: provide the name of the private DSA key. This option has to be used together with `-k`\n",
        "\t-k: provide the name of the keychain. This option has to be used together with `-n`\n",
        "\t-s: provide the path to the private EdDSA key\n",
        "\t--download-url-prefix: provide a static url that will be used as prefix for the url from where updates will be downloaded\n"
    )
}

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
func parseCommandLineOptions(argumentList: [String]) -> (privateDSAKey: SecKey?, privateEdString: String?, downloadUrlPrefix: URL?, archivesSourceDir: URL) {
    // if the option `-h` is in the argument list print the help dialog
    if argumentList.contains("-h") {
        printHelp()
        exit(1)
    }

    // make a mutable copy of the argument list
    var arguments = argumentList
    // remove the first element since this is the path to executable which we don't need
    arguments.removeFirst()

    // define the variables for the possible argument values
    var privateDSAKey: SecKey?
    var privateEdString: String?
    var downloadUrlPrefix: URL?
    var archivesSourceDir: URL

    // check if the private dsa key option is present
    if let privateDSAKeyOptionIndex = arguments.firstIndex(of: "-f") {
        // check that when accessing the value of the option we don't get out of bounds
        if privateDSAKeyOptionIndex + 1 >= arguments.count {
            print("Too few arguments were given")
            exit(1)
        }

        // get the private DSA key
        let privateKeyUrl = URL(fileURLWithPath: arguments[privateDSAKeyOptionIndex + 1])
        do {
            privateDSAKey = try loadPrivateDSAKey(at: privateKeyUrl)
        } catch {
            print("Unable to load DSA private key from", privateKeyUrl.path, "\n", error)
            exit(1)
        }

        // remove the already parsed arguments
        arguments.remove(at: privateDSAKeyOptionIndex)
        arguments.remove(at: privateDSAKeyOptionIndex + 1)
    }

    // check if the private dsa sould be loaded using the keyname and the name of the keychain
    if let keyNameOptionIndex = arguments.firstIndex(of: "-n"), let keychainNameOptionIndex = arguments.firstIndex(of: "-k") {
        // check that when accessing one of the values of the options we don't get out of bounds
        if keyNameOptionIndex + 1 >= arguments.count || keychainNameOptionIndex + 1 >= arguments.count {
            print("Too few arguments were given")
            exit(1)
        }

        // get the keyname and the keychain url to load the private DSA key
        let keyName: String = arguments[keyNameOptionIndex + 1]
        let keychainUrl: URL = URL(fileURLWithPath: arguments[keychainNameOptionIndex + 1])
        do {
            privateDSAKey = try loadPrivateDSAKey(named: keyName, fromKeychainAt: keychainUrl)
        } catch {
            print("Unable to load DSA private key '\(keyName)' from keychain at", keychainUrl.path, "\n", error)
            exit(1)
        }

        // remove the already parsed arguments
        arguments.remove(at: keyNameOptionIndex + 1)
        arguments.remove(at: keyNameOptionIndex)
        arguments.remove(at: arguments.firstIndex(of: "-k")! + 1)
        arguments.remove(at: keychainNameOptionIndex)
    }

    // check if the private EdDSA key string was given as an argument
    if let privateEdDSAKeyOptionIndex = arguments.firstIndex(of: "-s") {
        // check that when accessing the value of the option we don't get out of bounds
        if privateEdDSAKeyOptionIndex + 1 >= arguments.count {
            print("Too few arguments were given")
            exit(1)
        }

        // get the private EdDSA key string
        privateEdString = arguments[privateEdDSAKeyOptionIndex + 1]

        // remove the already parsed argument
        arguments.remove(at: privateEdDSAKeyOptionIndex + 1)
        arguments.remove(at: privateEdDSAKeyOptionIndex)
    }

    // check if a prefix for the download url of the archives was given
    if let downloadUrlPrefixOptionIndex = arguments.firstIndex(of: "--download-url-prefix") {
        // check that when accessing the value of the option we don't get out of bounds
        if downloadUrlPrefixOptionIndex + 1 >= arguments.count {
            print("Too few arguments were given")
            exit(1)
        }

        // get the download url prefix
        downloadUrlPrefix = URL(string: arguments[downloadUrlPrefixOptionIndex + 1])

        // remove the parsed argument
        arguments.remove(at: downloadUrlPrefixOptionIndex + 1)
        arguments.remove(at: downloadUrlPrefixOptionIndex)
    }

    // now that all command line options have been removed from the arguments array
    // there should only be the path to the private DSA key (if provided) path to the archives dir left
    if arguments.count == 2 {
        // if there are two arguments left they are the private DSA key and the path to the archives directory (in this order)
        // first get the private DSA key
        let privateKeyUrl = URL(fileURLWithPath: arguments[0])
        do {
            privateDSAKey = try loadPrivateDSAKey(at: privateKeyUrl)
        } catch {
            print("Unable to load DSA private key from", privateKeyUrl.path, "\n", error)
            exit(1)
        }

        // remove the parsed path to the DSA key
        arguments.removeFirst()
    }

    // now only the archives source dir is left
    archivesSourceDir = URL(fileURLWithPath: arguments[0], isDirectory: true)

    return (privateDSAKey, privateEdString, downloadUrlPrefix, archivesSourceDir)
}

func main() {
    let args = CommandLine.arguments
    if args.count < 2 {
        printUsage()
        exit(1)
    }

    var privateDSAKey: SecKey?
    var privateEdString: String?
    var downloadUrlPrefix: URL?
    var archivesSourceDir: URL

    (privateDSAKey, privateEdString, downloadUrlPrefix, archivesSourceDir) = parseCommandLineOptions(argumentList: args)

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
        exit(1)
    }
}

DispatchQueue.global().async(execute: {
    main()
    CFRunLoopStop(CFRunLoopGetMain())
})

CFRunLoopRun()
