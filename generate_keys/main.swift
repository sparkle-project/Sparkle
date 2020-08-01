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
//        kSecAttrSynchronizableAny as String: kCFBooleanTrue,
        kSecReturnData as String: kCFBooleanTrue!,
    ] as CFDictionary, &item)
    
    if res == errSecSuccess, let encoded = item as? Data, let keys = Data(base64Encoded: encoded) {
//        print("OK! Read the existing key saved in the Keychain.")
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

func generateKeyPair(makeSyncable: Bool) -> Data {
    var seed = Array<UInt8>(repeating: 0, count: 32)
    var publicEdKey = Array<UInt8>(repeating: 0, count: 32)
    var privateEdKey = Array<UInt8>(repeating: 0, count: 64)

    guard ed25519_create_seed(&seed) == 0 else {
        print("\nERROR: Unable to initialize random seed")
        exit(1)
    }
    ed25519_create_keypair(&publicEdKey, &privateEdKey, seed)

    let bothKeys = Data(privateEdKey) + Data(publicEdKey); // public key can't be derived from the private one
    let query = [
        // macOS doesn't support ed25519 keys, so we're forced to save the key as a "password"
        // and add some made-up service data for it to prevent it clashing with other passwords.
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "https://sparkle-project.org",
        kSecAttrAccount as String: "ed25519",

        kSecValueData as String: bothKeys.base64EncodedData() as CFData, // it's base64-encoded, because user may request to show it
        kSecAttrIsSensitive as String: kCFBooleanTrue!,
        kSecAttrIsPermanent as String: kCFBooleanTrue!,
        kSecAttrLabel as String: "Private key for signing Sparkle updates",
        kSecAttrComment as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(Data(publicEdKey).base64EncodedString())",
        kSecAttrDescription as String: "private key",
        
//        kSecAttrSynchronizable as String: (makeSyncable ? kCFBooleanTrue : kCFBooleanFalse)!,
    ] as CFDictionary
    
    let res = SecItemAdd(query, nil)

    if res == errSecSuccess {
//        print("OK! A new key has been generated and saved in the Keychain.")
        return Data(publicEdKey)
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

//let startEsc: String, endEsc: String
//if isatty(STDOUT_FILENO) != 0 {
//    startEsc = "\u{001b}[91m"
//    endEsc = "\u{001b}[m"
//} else {
//    startEsc = ""
//    endEsc = ""
//}
/*
    If you have iCloud Keychain enabled, the key may optionally be marked as
    syncable so it will be available on all devices logged into your iCloud account.

    \(startEsc)WARNING: Making a signing key syncable is NOT recommended!\(endEsc)
    
    The syncability option is provided because it provides a backup of the signing
    key should your local account data become lost or corrupted; loss of the key makes
    it impossible to release updates that will be accepted by Sparkle.
    
*/
print("""
    This tool uses the macOS Keychain to store a private key for signing app updates which
    will be distributed via Sparkle. The key will be associated with your user account.
    
    Note: You only need one signing key, no matter how many apps you embed Sparkle in.
    
    The keychain may ask permission for this tool to access an existing key, if one
    exists, or for permission to save the new key. You must allow access in order to
    successfully proceed.
    
    """)

if let pubKey = findPublicKey() {
    print("""
        A pre-existing signing key was found. This is how it should appear in your Info.plist:

            <key>SUPublicEDKey</key>
            <string>\(pubKey.base64EncodedString())</string>
            
        """)
} else {
//    print("A new signing key will be generated.")
//
//    print("""
//        Do you want to allow syncing the key to iCloud? [y/N]
//        """)
//    var makeSyncable: Bool? = nil
//    while makeSyncable == nil {
//        guard let response = readLine(strippingNewline: true) else { fatalError("EOF on stdin; can not continue") }
//        switch response.lowercased() {
//            case "y", "yes": makeSyncable = true
//            case "n", "no", "": makeSyncable = false
//            default: print("Unknown response. Allow key to sync to iCloud? [y/N]")
//        }
//    }
//
//    print("Generating a new signing key. This may take a moment, depending on your machine.")
    
    let pubKey = generateKeyPair(makeSyncable: false)
    
    print("""
        A key has been generated and saved in your keychain. Add the `SUPublicEDKey` key to
        the Info.plist of each app for which you intend to use Sparkle for distributing
        updates. It should appear like this:
        
            <key>SUPublicEDKey</key>
            <string>\(pubKey.base64EncodedString())</string>
        
        """)
}

print("Done.")
