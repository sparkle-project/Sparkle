//
//  main.swift
//  generate_keys
//
//  Created by Kornel on 15/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

import Foundation
import Security

private func commonKeychainItemAttributes() -> [String: Any] {
    /// Attributes used for both adding a new item and matching an existing one.
    return [
        /// The type of the item (a generic password).
        kSecClass        as String: kSecClassGenericPassword as String,
        
        /// The service string for the item (the Sparkle homepage URL).
        kSecAttrService  as String: "https://sparkle-project.org",
        
        /// The account name for the item (in this case, the key type).
        kSecAttrAccount  as String: "ed25519",
        
        /// The protocol used by the service (not actually used, so we claim SSH).
        kSecAttrProtocol as String: kSecAttrProtocolSSH as String,
    ]
}

private func failure(_ message: String) -> Never {
    /// Checking for both `TERM` and `isatty()` correctly detects Xcode.
    if ProcessInfo.processInfo.environment["TERM"] != nil && isatty(STDOUT_FILENO) != 0 {
        print("\u{001b}[1;91mERROR:\u{001b}[0m ", terminator: "")
    } else {
        print("ERROR: ", terminator: "")
    }
    print(message)
    exit(1)
}

func findPublicKey() -> Data? {
    var item: CFTypeRef?
    let res = SecItemCopyMatching(commonKeychainItemAttributes().merging([
        /// Return a matched item's value as a CFData object.
        kSecReturnData as String: kCFBooleanTrue!,
    ], uniquingKeysWith: { $1 }) as CFDictionary, &item)
    
    switch res {
        case errSecSuccess:
            if let keys = (item as? Data).flatMap({ Data(base64Encoded: $0) }) {
                return keys[64...]
            } else {
                failure("""
                    Item found, but is corrupt or has been overwritten!

                    Please delete the existing item from the keychain and try again.
                    """)
            }
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed:
            failure("""
                Access denied. Can't check existing keys in the keychain.
                
                Go to Keychain Access.app, lock the login keychain, then unlock it again.
                """)
        case errSecUserCanceled:
            failure("""
                User canceled the authorization request.
                
                To retry, run this tool again.
                """)
        case errSecInteractionNotAllowed:
            failure("""
                The operating system has blocked access to the Keychain.
                
                You may be trying to run this command from a script over SSH, which is not supported.
                """)
        case let res:
            print("""
                Unable to access an existing item in the Keychain due to an unknown error: \(res).
                
                You can look up this error at <https://osstatus.com/search/results?search=\(res)>
                """)
                // Note: Don't bother percent-encoding `res`, it's always an integer value and will not need escaping.
    }
    exit(1)
}

func generateKeyPair() -> Data {
    var seed = Array<UInt8>(repeating: 0, count: 32)
    var publicEdKey = Array<UInt8>(repeating: 0, count: 32)
    var privateEdKey = Array<UInt8>(repeating: 0, count: 64)

    guard ed25519_create_seed(&seed) == 0 else {
        failure("Unable to initialize random seed. Try restarting your computer.")
    }
    ed25519_create_keypair(&publicEdKey, &privateEdKey, seed)

    let query = commonKeychainItemAttributes().merging([
        /// Mark the new item as sensitive (requires keychain password to export - e.g. a private key).
        kSecAttrIsSensitive as String: kCFBooleanTrue!,

        /// Mark the new item as permanent (supposedly, "stored in the keychain when created", but not actually
        /// used for generic passwords - we set it anyway for good measure).
        kSecAttrIsPermanent as String: kCFBooleanTrue!,

        /// The label of the new item (shown as its name/title in Keychain Access).
        kSecAttrLabel       as String: "Private key for signing Sparkle updates",

        /// A comment regarding the item's content (can be viewed in Keychain Access; we give the public key here).
        kSecAttrComment     as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(Data(publicEdKey).base64EncodedString())",

        /// A short description of the item's contents (shown as "kind" in Keychain Access").
        kSecAttrDescription as String: "private key",

        /// The actual data content of the new item.
        kSecValueData       as String: Data(privateEdKey + publicEdKey).base64EncodedData() as CFData
    
    ], uniquingKeysWith: { $1 }) as CFDictionary
    
    switch SecItemAdd(query, nil) {
        case errSecSuccess:
            return Data(publicEdKey)
        case errSecDuplicateItem:
            failure("You already have a conflicting key in your Keychain which was not found during lookup.")
        case errSecAuthFailed:
            failure("""
                System denied access to the Keychain. Unable to save the new key.
                Go to Keychain Access.app, lock the login keychain, then unlock it again.
                """)
        case let res:
            failure("""
                The key could not be saved to the Keychain due to an unknown error: \(res).
                
                You can look up this error at <https://osstatus.com/search/results?search=\(res)>
                """)
    }
    exit(1)
}

/// Once it's safe to require Swift 5.3 and Xcode 12 for this code, rename this file to `generate_keys.swift` and
/// replace this function with a class tagged with `@main`.
func entryPoint() {
    let isLookupMode = (CommandLine.arguments.dropFirst().first.map({ $0 == "-p" }) ?? false)

    /// If not in lookup-only mode, give an intro blurb.
    if !isLookupMode {
        print("""
            This tool uses the macOS Keychain to store a private key for signing app updates which
            will be distributed via Sparkle. The key will be associated with your user account.
            
            Note: You only need one signing key, no matter how many apps you embed Sparkle in.
            
            The keychain may ask permission for this tool to access an existing key, if one
            exists, or for permission to save the new key. You must allow access in order to
            successfully proceed.
            
            """)
    }
    
    switch (findPublicKey(), isLookupMode) {
        /// Existing key found, lookup mode - print just the pubkey and exit
        case (.some(let pubKey), true):
            print(pubKey.base64EncodedString())
        
        /// Existing key found, normal mode - print instructions blurb and pubkey
        case (.some(let pubKey), false):
            print("""
                A pre-existing signing key was found. This is how it should appear in your Info.plist:

                    <key>SUPublicEDKey</key>
                    <string>\(pubKey.base64EncodedString())</string>
                    
                """)
        
        /// No existing key, lookup mode - error out
        case (.none, true):
            failure("No existing signing key found!")
        
        /// No existing key, normal mode - generate a new one
        case (.none, false):
            print("Generating a new signing key. This may take a moment, depending on your machine.")
            
            let pubKey = generateKeyPair()
            
            print("""
                A key has been generated and saved in your keychain. Add the `SUPublicEDKey` key to
                the Info.plist of each app for which you intend to use Sparkle for distributing
                updates. It should appear like this:
                
                    <key>SUPublicEDKey</key>
                    <string>\(pubKey.base64EncodedString())</string>
                
                """)
    }
}

// Dispatch to a function because `@main` isn't stable yet at the time of this writing and top-level code is finicky.
entryPoint()
