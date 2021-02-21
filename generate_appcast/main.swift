//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

var verbose = false

// Enum that contains keys for command-line arguments
struct CommandLineArguments {
    var privateDSAKey : SecKey?
    var privateEdString : String?
    var downloadURLPrefix : URL?
    var releaseNotesURLPrefix: URL?
    var outputPathURL: URL?
    var archivesSourceDir: URL?
}

func printUsage() {
    let command = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
    let usage = """

Generate appcast from a directory of Sparkle update archives

Usage: \(command) [OPTIONS] [ARCHIVES_FOLDER]
    -h: prints this message
    -f: provide the path to the private DSA key
    -n: provide the name of the private DSA key. This option must be used with `-k`
    -k: provide the name of the keychain. This option must be used with `-n`
    -s: provide the private EdDSA key (128 characters)
    -o: provide a filename for the generated appcast (allowed when only one will be created)
    
    --download-url-prefix: provide a prefix used to construct URLs for update downloads
    --release-notes-url-prefix: provide a prefix used to construct URLs for release notes
    
Examples:
    \(command) ./my-app-release-zipfiles/
    \(command) -o appcast-name.xml ./my-app-release-zipfiles/
    
    \(command) dsa_priv.pem ./my-app-release-zipfiles/ [DEPRECATED]

Appcast files and deltas will be written to the archives directory.
Note that pkg-based updates are not supported.

"""
    
    print(usage)
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
 * Parses all possible command line options and returns a struct that contains them
 */
func parseCommandLineOptions() -> CommandLineArguments {
    var arguments = CommandLine.arguments
    
    // If there are fewer than two arguments (the name of the application +
    // the required archive directory), or if `-h` is in the argument list,
    // then show the usage message
    if arguments.count < 2  || arguments.contains("-h") {
        printUsage()
        exit(1)
    }
    
    // Remove the first element since this is the path to executable which we don't need
    arguments.removeFirst()

    // Create the struct that will hold the parsed args
    var commandLineArguments = CommandLineArguments()

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
            commandLineArguments.privateDSAKey = try loadPrivateDSAKey(at: privateKeyUrl)
        } catch {
            print("Unable to load DSA private key from", privateKeyUrl.path, "\n", error)
            exit(1)
        }

        // remove the already parsed arguments
        arguments.remove(at: privateDSAKeyOptionIndex + 1)
        arguments.remove(at: privateDSAKeyOptionIndex)
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
            commandLineArguments.privateDSAKey = try loadPrivateDSAKey(named: keyName, fromKeychainAt: keychainUrl)
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
        commandLineArguments.privateEdString = arguments[privateEdDSAKeyOptionIndex + 1]

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
        commandLineArguments.downloadURLPrefix = URL(string: arguments[downloadUrlPrefixOptionIndex + 1])

        // remove the parsed argument
        arguments.remove(at: downloadUrlPrefixOptionIndex + 1)
        arguments.remove(at: downloadUrlPrefixOptionIndex)
    }
    
    // Check if a URL prefix was specified for the release notes
    if let releaseNotesURLPrefixOptionIndex = arguments.firstIndex(of: "--release-notes-url-prefix") {
        if releaseNotesURLPrefixOptionIndex + 1 >= arguments.count {
            print("Too few arguments were given")
            exit(1)
        }
        
        // Get the URL prefix for the release notes
        commandLineArguments.releaseNotesURLPrefix = URL(string: arguments[releaseNotesURLPrefixOptionIndex + 1])
        
        // Remove the parsed argument
        arguments.remove(at: releaseNotesURLPrefixOptionIndex + 1)
        arguments.remove(at: releaseNotesURLPrefixOptionIndex)
    }
    
    // Check if an output filename was specified
    if let outputFilenameOptionIndex = arguments.firstIndex(of: "-o") {
        // check that when accessing the value of the option we don't get out of bounds
        if outputFilenameOptionIndex + 1 >= arguments.count {
            print("Too few arguments were given")
            exit(1)
        }
        
        // Get the URL prefix for the release notes
        commandLineArguments.outputPathURL = URL(fileURLWithPath: arguments[outputFilenameOptionIndex + 1])
        
        // Remove the parsed argument
        arguments.remove(at: outputFilenameOptionIndex + 1)
        arguments.remove(at: outputFilenameOptionIndex)
    }

    // now that all command line options have been removed from the arguments array
    // there should only be the path to the private DSA key (if provided) path to the archives dir left
    if arguments.count == 2 {
        // if there are two arguments left they are the private DSA key and the path to the archives directory (in this order)
        // first get the private DSA key
        let privateKeyURL = URL(fileURLWithPath: arguments[0])
        do {
            commandLineArguments.privateDSAKey = try loadPrivateDSAKey(at: privateKeyURL)
        } catch {
            print("Unable to load DSA private key from", privateKeyURL.path, "\n", error)
            exit(1)
        }

        // remove the parsed path to the DSA key
        arguments.removeFirst()
    }

    // now only the archives source dir is left
    if let archivesSourceDir = arguments.first {
        commandLineArguments.archivesSourceDir = URL(fileURLWithPath: archivesSourceDir, isDirectory: true)
    } else {
        print("Archive folder must be specified")
        exit(1);
    }

    return commandLineArguments
}

func main() {
    // Parse the command line arguments
    let args = parseCommandLineOptions()
    
    // If parsing the command line options was successful, then
    // the archivesSourceDir must exist
    let archivesSourceDir = args.archivesSourceDir!
    
    // Extract the keys
    let keys = loadPrivateKeys(args.privateDSAKey, args.privateEdString)
    
    do {
        let allUpdates = try makeAppcast(archivesSourceDir: archivesSourceDir, keys: keys, verbose: verbose)

        // If a URL prefix was provided, set on the archive items
        if args.downloadURLPrefix != nil || args.releaseNotesURLPrefix != nil {
            for (_, archiveItems) in allUpdates {
                for archiveItem in archiveItems {
                    if let downloadURLPrefix = args.downloadURLPrefix {
                        archiveItem.downloadUrlPrefix = downloadURLPrefix
                    }
                    if let releaseNotesURLPrefix = args.releaseNotesURLPrefix {
                        archiveItem.releaseNotesURLPrefix = releaseNotesURLPrefix
                    }
                }
            }
        }

        // If a (single) output filename was specified on the command-line, but more than one
        // appcast file was found in the archives, then it's an error.
        if let outputPathURL = args.outputPathURL,
            allUpdates.count > 1 {
            print("Cannot write to \(outputPathURL.path): multiple appcasts found")
            exit(1);
        }
        
        for (appcastFile, updates) in allUpdates {
            // If an output filename was specified, use it.
            // Otherwise, use the name of the appcast file found in the archive.
            let appcastDestPath = args.outputPathURL ?? URL(fileURLWithPath: appcastFile,
                                                            relativeTo: archivesSourceDir)
            
            // Write the appcast
            try writeAppcast(appcastDestPath: appcastDestPath, updates: updates)
            
            // Inform the user, pluralizing "update" if necessary
            let updateString = (updates.count == 1) ? "update" : "updates"
            print("Wrote \(updates.count) \(updateString) to: \(appcastDestPath.path)")
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
