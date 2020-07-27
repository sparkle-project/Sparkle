//
//  main.swift
//  sign_update
//
//  Created by Kornel on 16/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

import Foundation
import Security

func parseKeysFromString(_ string: String) -> (Data, Data) {
    if string.count != 128 {
        print("ERROR! key not found in the argument. Please provide a valid key.")
        exit(1)
    }
    let keys = Data(base64Encoded: string)!
    return (keys[0..<64], keys[64...])
}
func findKeys() -> (Data, Data) {
    var item: CFTypeRef?
    let res = SecItemCopyMatching([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "https://sparkle-project.org",
        kSecAttrAccount as String: "ed25519",
        kSecAttrProtocol as String: kSecAttrProtocolSSH,
        kSecReturnData as String: kCFBooleanTrue,
        ] as CFDictionary, &item)
    if res == errSecSuccess, let encoded = item as? Data, let keys = Data(base64Encoded: encoded) {
        return (keys[0..<64], keys[64..<(64+32)])
    } else if res == errSecItemNotFound {
        print("ERROR! Signing key not found. Please run generate_keys tool first.")
    } else if res == errSecAuthFailed {
        print("ERROR! Access denied. Can't get keys from the keychain.")
        print("Go to Keychain Access.app, lock the login keychain, then unlock it again.")
    } else if res == errSecUserCanceled {
        print("ABORTED! You've cancelled the request to read the key from the Keychain. Please run the tool again.")
    } else if res == errSecInteractionNotAllowed {
        print("ERROR! The operating system has blocked access to the Keychain.")
    } else {
        print("ERROR! Unable to access required key in the Keychain", res, "(you can look it up at osstatus.com)")
    }
    exit(1)
}

func edSignature(data: Data, publicEdKey: Data, privateEdKey: Data) -> String {
    assert(publicEdKey.count == 32)
    assert(privateEdKey.count == 64)
    let len = data.count
    var output = Data(count: 64)
    output.withUnsafeMutableBytes({ (output: UnsafeMutablePointer<UInt8>) in
        data.withUnsafeBytes({ (data: UnsafePointer<UInt8>) in
            publicEdKey.withUnsafeBytes({ (publicEdKey: UnsafePointer<UInt8>) in
                privateEdKey.withUnsafeBytes({ (privateEdKey: UnsafePointer<UInt8>) in
                    ed25519_sign(output, data, len, publicEdKey, privateEdKey)
                })
            })
        })
    })
    return output.base64EncodedString()
}

let args = CommandLine.arguments
if args.count != 2 && !(args.count == 4 && args[1] == "-s") {
    print("Usage: \n")
    print("\t1. \(args[0]) <archive to sign>\n\tPrivate EdDSA (ed25519) key is automatically read from the Keychain.\n")
    print("\t2 \(args[0]) -s <key> <archive to sign>\n\tThe key's length is 128 that includes private and public key.\n")
    exit(1)
}
let (priv, pub) = args.count == 2 ? findKeys() : parseKeysFromString(args[2])
let filePath = args.count == 2 ? args[1] : args[3]

do {
    let data = try Data.init(contentsOf: URL.init(fileURLWithPath: filePath), options: .mappedIfSafe)
    let sig = edSignature(data: data, publicEdKey: pub, privateEdKey: priv)
    print("sparkle:edSignature=\"\(sig)\" length=\"\(data.count)\"")
} catch {
    print("ERROR: ", error)
}
