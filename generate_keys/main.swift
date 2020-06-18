//
//  main.swift
//  generate_keys
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

import Foundation
import Security
import ArgumentParser

struct GenerateKeys: ParsableCommand {
    static let configuration: CommandConfiguration = {
        let commandName = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent
        return CommandConfiguration(commandName: commandName, abstract: "Generate, print, or export Ed25519 key pair for Sparkle update signing.")
    }()

    @Flag(name: [.short, .customLong("export")], help: ArgumentHelp(#"Export saved key pair from the default keychain to a stand-alone keychain, with ".keychain" appended.\#nIf <keychain-file> is a directory, a default name of "sparkle_export" will be used."#, valueName: "file"))
    var export: Bool

    @Argument(help: ArgumentHelp(#"The keychain file to search, add, or export to.\#nIf no keychain at exists at <keychain-file> and --export is not specified, one will be created."#), transform: { URL(fileURLWithPath: $0) })
    var keychainFile: URL?

    func messageForSecError(_ err: OSStatus) -> String {
        return SecCopyErrorMessageString(err, nil) as String? ?? "\(err) (you can look it up at osstatus.com)"
    }

    var keychainItemBaseQueryDictionary: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "https://sparkle-project.org",
            kSecAttrAccount as String: "ed25519",
        ]
    }

    var keychainItemDictionaryForSearching: [String: Any] {
        var query = keychainItemBaseQueryDictionary
        query[kSecReturnData as String] = true
        return query
    }

    func keychainItemQueryDictionary(forAddingKeys bothKeys: Data) throws -> [String: Any] {
        guard bothKeys.count == 96 else {
            print("Data for both keys must have length 96!\n")
            throw ExitCode(1)
        }

        let baseQuery = keychainItemBaseQueryDictionary
        return baseQuery.merging([
            // macOS doesn't support ed25519 keys, so we're forced to save the key as a "password"
            // and add some made-up service data for it to prevent it clashing with other passwords.
            kSecValueData as String: bothKeys.base64EncodedData(), // it's base64-encoded, because user may request to show it
            kSecAttrIsSensitive as String: true,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: "Private key for signing Sparkle updates",
            kSecAttrComment as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(bothKeys[64...].base64EncodedString())",
            kSecAttrDescription as String: "private key",
        ]) { $1 }
    }

    func findKeyPair(in keychainURL: URL? = nil) throws -> Data? {
        var item: CFTypeRef?

        var query = keychainItemDictionaryForSearching

        if let keychainURL = keychainURL {
            var keychain: SecKeychain?
            let res = SecKeychainOpen(keychainURL.path, &keychain)

            if res != errSecSuccess {
                print("Couldn't open keychain at \(keychainURL.relativePath): \(messageForSecError(res)).")
                throw ExitCode(1)
            }

            query[kSecMatchSearchList as String] = [keychain]
        }

        let res = SecItemCopyMatching(query as CFDictionary, &item)

        if res == errSecSuccess, let encoded = item as? Data, let keys = Data(base64Encoded: encoded) {
            print("OK! Read the existing key saved in the Keychain.")
            return keys
        } else if res == errSecItemNotFound {
            return nil
        } else if res == errSecAuthFailed {
            print("\nERROR! Access denied. Can't check existing keys in the keychain.")
            print("Go to Keychain Access.app, lock the login keychain, then unlock it again.")
        } else if res == errSecUserCanceled {
            print("\nABORTED! You've cancelled the request to read the key from the Keychain. Please run the tool again.")
        } else if res == errSecInteractionNotAllowed {
            print("\nERROR! The operating system has blocked access to the Keychain.")
        } else {
            print("\nERROR! Unable to access existing item in the Keychain: ", messageForSecError(res))
        }

        throw ExitCode(1)
    }

    func findPublicKey(in keychainURL: URL? = nil) throws -> Data? {
        guard let keyPair = try findKeyPair(in: keychainURL) else { return nil }
        return keyPair[64...]
    }

    func generateKeyPair(in keychainURL: URL? = nil) throws -> Data {
        var seed = Data(count: 32)
        var publicEdKey = Data(count: 32)
        var privateEdKey = Data(count: 64)

        if !seed.withUnsafeMutableBytes({ (seed: UnsafeMutableRawBufferPointer) in
            let seed = seed.bindMemory(to: UInt8.self)
            return 0 == ed25519_create_seed(seed.baseAddress)
        }) {
            print("\nERROR: Unable to initialize random seed")
            throw ExitCode(1)
        }

        seed.withUnsafeBytes({(seed: UnsafeRawBufferPointer) in
            publicEdKey.withUnsafeMutableBytes({(publicEdKey: UnsafeMutableRawBufferPointer) in
                privateEdKey.withUnsafeMutableBytes({(privateEdKey: UnsafeMutableRawBufferPointer) in
                    let seed = seed.bindMemory(to: UInt8.self)
                    let publicEdKey = publicEdKey.bindMemory(to: UInt8.self)
                    let privateEdKey = privateEdKey.bindMemory(to: UInt8.self)

                    ed25519_create_keypair(publicEdKey.baseAddress, privateEdKey.baseAddress, seed.baseAddress)
                })
            })
        })

        let bothKeys = privateEdKey + publicEdKey; // public key can't be derived from the private one
        var query = try keychainItemQueryDictionary(forAddingKeys: bothKeys)

        if let keychainURL = keychainURL {
            let (keychain, _) = try createNewKeychain(at: keychainURL)

            query[kSecUseKeychain as String] = keychain
        }

        let res = SecItemAdd(query as CFDictionary, nil)

        if res == errSecSuccess {
            print("OK! A new key has been generated and saved in the Keychain.")
        } else if res == errSecDuplicateItem {
            print("\nERROR: You already have a previously generated key in the Keychain")
        } else if res == errSecAuthFailed {
            print("\nERROR: System denied access to the Keychain. Unable to save the new key")
            print("Go to Keychain Access.app, lock the login keychain, then unlock it again.")
        } else {
            print("\nERROR: The key could not be saved to the Keychain. error:", messageForSecError(res))
        }
        throw ExitCode(1)
    }

    func createNewKeychain(at keychainURL: URL? = nil) throws -> (keychain: SecKeychain, resolvedURL: URL) {
        var url = keychainURL ?? URL(fileURLWithPath: ".")

        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            if values.isDirectory! {
                url.appendPathComponent("sparkle_export")
            }
        }

        if url.pathExtension != "keychain" && url.pathExtension != "keychain-db" {
            url.appendPathExtension("keychain")
        }

        var keychain: SecKeychain?
        let res = SecKeychainCreate(url.path, 0, nil, true, nil, &keychain)

        if res != errSecSuccess {
            print("\nERROR: Couldn't create new keychain.")

            if res == errSecDuplicateKeychain {
                print("       File already exists at \(url.relativePath)")
            } else {
                print("       \(messageForSecError(res))")
            }

            throw ExitCode(1)
        }

        return (keychain!, url)
    }

    func createNewKeychain(withKeyPair bothKeys: Data, at keychainURL: URL?) throws {
        let (keychain, url) = try createNewKeychain(at: keychainURL)
        var query = try keychainItemQueryDictionary(forAddingKeys: bothKeys)
        query[kSecUseKeychain as String] = keychain

        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            print("Couldn't add keychain item to new keychain.")
            throw ExitCode(1)
        }

        print("Copied key to \(url.relativePath).")
    }

    func run() throws {
        print("This tool uses macOS Keychain to store the Sparkle private key.")
        print("If the Keychain prompts you for permission, please allow it.")

        if export {
            if let keyPair = try findKeyPair() {
                try createNewKeychain(withKeyPair: keyPair, at: keychainFile)
            }
        } else {
            let pubKey = try findPublicKey(in: keychainFile) ?? generateKeyPair(in: keychainFile)
            print("\nIn your app's Info.plist set SUPublicEDKey to:\n\(pubKey.base64EncodedString())\n")
        }
    }

}

GenerateKeys.main()
