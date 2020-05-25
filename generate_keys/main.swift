//
//  main.swift
//  generate_keys
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

import Foundation
import Security

func findPublicKey() -> Data? {
    var item: CFTypeRef?
    let res = SecItemCopyMatching([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "https://sparkle-project.org",
        kSecAttrAccount as String: "ed25519",
        kSecAttrProtocol as String: kSecAttrProtocolSSH,
        kSecReturnData as String: kCFBooleanTrue,
    ] as CFDictionary, &item)
    if res == errSecSuccess, let encoded = item as? Data, let keys = Data(base64Encoded: encoded) {
        print("OK! Read the existing key saved in the Keychain.")
        return keys[64...]
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
        print("\nERROR! Unable to access existing item in the Keychain", res, "(you can look it up at osstatus.com)")
    }
    exit(1)
}

func generateKeyPair() -> Data {
    var seed = Data(count: 32)
    var publicEdKey = Data(count: 32)
    var privateEdKey = Data(count: 64)

    if !seed.withUnsafeMutableBytes { (seed: UnsafeMutablePointer<UInt8>) in 0 == ed25519_create_seed(seed)} {
        print("\nERROR: Unable to initialize random seed")
        exit(1)
    }

    seed.withUnsafeBytes({(seed: UnsafePointer<UInt8>) in
        publicEdKey.withUnsafeMutableBytes({(publicEdKey: UnsafeMutablePointer<UInt8>) in
            privateEdKey.withUnsafeMutableBytes({(privateEdKey: UnsafeMutablePointer<UInt8>) in
                ed25519_create_keypair(publicEdKey, privateEdKey, seed)
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
        kSecAttrIsSensitive as String: kCFBooleanTrue,
        kSecAttrIsPermanent as String: kCFBooleanTrue,
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
        print("\nERROR: The key could not be saved to the Keychain. error: \(res) (you can look it up at osstatus.com)")
    }
    exit(1)
}

print("This tool uses macOS Keychain to store the Sparkle private key.")
print("If the Keychain prompts you for permission, please allow it.")
let pubKey = findPublicKey() ?? generateKeyPair()
print("\nIn your app's Info.plist set SUPublicEDKey to:\n\(pubKey.base64EncodedString())\n")
