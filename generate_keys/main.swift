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

    @Option(name: [.short, .customLong("export")], help: ArgumentHelp(#"Export saved key pair to a stand-alone keychain, with ".keychain" appended.\#nIf the value is a directory, a default name of "sparkle_export" will be used."#, valueName: "file"))
    var exportFile: String?

    func messageForSecError(_ err: OSStatus) -> String {
        return SecCopyErrorMessageString(err, nil) as String? ?? "\(err) (you can look it up at osstatus.com)"
    }

    func findKeyPair() throws -> Data? {
        var item: CFTypeRef?
        let res = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "https://sparkle-project.org",
            kSecAttrAccount as String: "ed25519",
            kSecAttrProtocol as String: kSecAttrProtocolSSH,
            kSecReturnData as String: true,
            ] as CFDictionary, &item)

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

    func findPublicKey() throws -> Data? {
        guard let keyPair = try findKeyPair() else { return nil }
        return keyPair[64...]
    }

    func generateKeyPair() throws -> Data {
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
        let query = [
            // macOS doesn't support ed25519 keys, so we're forced to save the key as a "password"
            // and add some made-up service data for it to prevent it clashing with other passwords.
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "https://sparkle-project.org",
            kSecAttrAccount as String: "ed25519",

            kSecValueData as String: bothKeys.base64EncodedData() as CFData, // it's base64-encoded, because user may request to show it
            kSecAttrIsSensitive as String: true,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: "Private key for signing Sparkle updates",
            kSecAttrComment as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(publicEdKey.base64EncodedString())",
            kSecAttrDescription as String: "private key",
            ] as CFDictionary
        let res = SecItemAdd(query, nil)

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

    func absolutePathForPath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        return currentDirectory.appendingFormat("/%@", path)
    }

    func createNewKeychain(withKeyPair bothKeys: Data, named name: String = "sparkle_export") throws {
        var keychainPath = absolutePathForPath(name)
        var finalName = name

        let url = URL(fileURLWithPath: keychainPath)
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            if values.isDirectory! {
                finalName.append("/sparkle_export")
                keychainPath.append("/sparkle_export")
            }
        }

        if !keychainPath.hasSuffix(".keychain") && !keychainPath.hasSuffix(".keychain-db") {
            finalName.append(".keychain")
            keychainPath.append(".keychain")
        }

        var keychain: SecKeychain?
        let res = SecKeychainCreate(keychainPath, 0, nil, true, nil, &keychain)
        if res != errSecSuccess {
            print("\nERROR: Couldn't create new keychain.")

            if res == errSecDuplicateKeychain {
                print("       File already exists at \(finalName)")
            } else {
                print("       \(messageForSecError(res))")
            }

            throw ExitCode(1)
        }

        let query = [
            // macOS doesn't support ed25519 keys, so we're forced to save the key as a "password"
            // and add some made-up service data for it to prevent it clashing with other passwords.
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "https://sparkle-project.org",
            kSecAttrAccount as String: "ed25519",

            kSecValueData as String: bothKeys.base64EncodedData() as CFData, // it's base64-encoded, because user may request to show it
            kSecAttrIsSensitive as String: true,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: "Private key for signing Sparkle updates",
            kSecAttrComment as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(bothKeys[64...].base64EncodedString())",
            kSecAttrDescription as String: "private key",

            kSecUseKeychain as String: keychain!
            ] as CFDictionary

        guard SecItemAdd(query, nil) == errSecSuccess else {
            print("Couldn't add keychain item to new keychain.")
            throw ExitCode(1)
        }

        print("Copied key to \(finalName).")
    }

    func run() throws {
        print("This tool uses macOS Keychain to store the Sparkle private key.")
        print("If the Keychain prompts you for permission, please allow it.")

        if let exportFile = exportFile {
            if let keyPair = try findKeyPair() {
                try createNewKeychain(withKeyPair: keyPair, named: exportFile)
            }
        } else {

            let pubKey = try findPublicKey() ?? generateKeyPair()
            print("\nIn your app's Info.plist set SUPublicEDKey to:\n\(pubKey.base64EncodedString())\n")
        }
    }

}

GenerateKeys.main()
