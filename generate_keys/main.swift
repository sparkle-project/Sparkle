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

let PRIVATE_KEY_LABEL = "Private key for signing Sparkle updates"

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

func findKeyPair() -> Data? {
    var item: CFTypeRef?
    let res = SecItemCopyMatching(commonKeychainItemAttributes().merging([
        /// Return a matched item's value as a CFData object.
        kSecReturnData as String: kCFBooleanTrue!,
    ], uniquingKeysWith: { $1 }) as CFDictionary, &item)
    
    switch res {
        case errSecSuccess:
            if let keys = (item as? Data).flatMap({ Data(base64Encoded: $0) }) {
                return keys
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

func generateKeyPair() -> (publicEdKey: Data, privateEdKey: Data) {
    var seed = Array<UInt8>(repeating: 0, count: 32)
    var publicEdKey = Array<UInt8>(repeating: 0, count: 32)
    var privateEdKey = Array<UInt8>(repeating: 0, count: 64)

    guard ed25519_create_seed(&seed) == 0 else {
        failure("Unable to initialize random seed. Try restarting your computer.")
    }
    ed25519_create_keypair(&publicEdKey, &privateEdKey, seed)
    
    return (Data(publicEdKey), Data(privateEdKey))
}

func storeKeyPair(publicEdKey: Data, privateEdKey: Data) {
    let query = commonKeychainItemAttributes().merging([
        /// Mark the new item as sensitive (requires keychain password to export - e.g. a private key).
        kSecAttrIsSensitive as String: kCFBooleanTrue!,

        /// Mark the new item as permanent (supposedly, "stored in the keychain when created", but not actually
        /// used for generic passwords - we set it anyway for good measure).
        kSecAttrIsPermanent as String: kCFBooleanTrue!,

        /// The label of the new item (shown as its name/title in Keychain Access).
        kSecAttrLabel       as String: PRIVATE_KEY_LABEL,

        /// A comment regarding the item's content (can be viewed in Keychain Access; we give the public key here).
        kSecAttrComment     as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(Data(publicEdKey).base64EncodedString())",

        /// A short description of the item's contents (shown as "kind" in Keychain Access").
        kSecAttrDescription as String: "private key",

        /// The actual data content of the new item.
        kSecValueData       as String: (privateEdKey + publicEdKey).base64EncodedData() as CFData
    
    ], uniquingKeysWith: { $1 }) as CFDictionary
    
    switch SecItemAdd(query, nil) {
        case errSecSuccess:
            break
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
}

func printNewPublicKeyUsage(_ publicKey: Data) {
    print("""
        A key has been generated and saved in your keychain. Add the `SUPublicEDKey` key to
        the Info.plist of each app for which you intend to use Sparkle for distributing
        updates. It should appear like this:
        
            <key>SUPublicEDKey</key>
            <string>\(publicKey.base64EncodedString())</string>
        
        """)
}

/// Once it's safe to require Swift 5.3 and Xcode 12 for this code, rename this file to `generate_keys.swift` and
/// replace this function with a class tagged with `@main`.
func entryPoint() {
    let arguments = CommandLine.arguments
    let programName = arguments.first ?? "generate_keys"
    
    let mode = arguments.count > 1 ? arguments[1] : nil

    /// If not in any mode, give an intro blurb.
    if mode == nil {
        print("""
            Usage: \(programName) [-p] [-x private-key-file] [-f private-key-file]
            
            This tool generates a public & private keys and uses the macOS Keychain to store
            the private key for signing app updates which will be distributed via Sparkle.
            This key will be associated with your user account.
            
            Note: You only need one signing key, no matter how many apps you embed Sparkle in.
            
            The keychain may ask permission for this tool to access an existing key, if one
            exists, or for permission to save the new key. You must allow access in order to
            successfully proceed.

            Additional Options:
            -p
                Looks up and just prints the existing public key stored in the Keychain.

            -x private-key-file
                Exports your private key from your login keychain and writes it to private-key-file. Note the contents of
                this sensitive exported file are the same as the password to the \"\(PRIVATE_KEY_LABEL)\" item in
                your keychain.
            
            -f private-key-file
                Imports the private key from private-key-file into your keychain instead of generating a new key.
                This file has likely been exported via -x option from another machine.
                Any existing \"\(PRIVATE_KEY_LABEL)\" items listed in Keychain Access may need to be removed manually first before proceeding.

            ----------------------------------------------------------------------------------------------------

            """)
    }
    
    switch mode {
    case .some("-p"):
        /// Lookup mode - print just the pubkey and exit
        if let keyPair = findKeyPair() {
            let pubKey = keyPair[64...]
            print(pubKey.base64EncodedString())
        } else {
            failure("No existing signing key found!")
        }
    case .some("-f"):
        /// Import mode - import the specifed key-pair file
        guard arguments.count > 2 else {
            failure("private-key-file was not specified")
        }
        
        let privateAndPublicBase64KeyFile = arguments[2]
        let privateAndPublicBase64Key: String
        do {
            privateAndPublicBase64Key = try String(contentsOfFile: privateAndPublicBase64KeyFile)
        } catch {
            failure("Failed to read private-key-file: \(error)")
        }
        
        guard let privateAndPublicKey = Data(base64Encoded: privateAndPublicBase64Key.trimmingCharacters(in: .whitespacesAndNewlines), options: .init()) else {
            failure("Failed to decode base64 encoded key data from: \(privateAndPublicBase64Key)")
        }
        
        guard privateAndPublicKey.count == 64 + 32 else {
            failure("Imported key must be 96 bytes decoded. Instead it is \(privateAndPublicKey.count) bytes decoded.")
        }
        
        print("Importing signing key..")
        
        let publicKey = privateAndPublicKey[64...]
        let privateKey = privateAndPublicKey[0..<64]
        
        storeKeyPair(publicEdKey: publicKey, privateEdKey: privateKey)
        
        printNewPublicKeyUsage(publicKey)
        
    case .some("-x"):
        /// Export mode - export the key-pair file from the user's keychain
        guard arguments.count > 2 else {
            failure("private-key-file was not specified")
        }
        
        let exportURL = URL(fileURLWithPath: arguments[2])
        if let reachable = try? exportURL.checkResourceIsReachable(), reachable {
            failure("private-key-file already exists: \(exportURL.path)")
        }
        
        guard let keyPair = findKeyPair() else {
            failure("No existing signing key found!")
        }
        
        do {
            try keyPair.base64EncodedString().write(to: exportURL, atomically: true, encoding: .utf8)
        } catch {
            failure("Failed to write exported file: \(error)")
        }
        
    case .some(let unknownOption):
        failure("Unknown option: \(unknownOption)")
    
    case nil:
        /// Default mode - find an existing public key and print its usage, or generate new keys
        if let keyPair = findKeyPair() {
            let pubKey = keyPair[64...]
            print("""
                A pre-existing signing key was found. This is how it should appear in your Info.plist:

                    <key>SUPublicEDKey</key>
                    <string>\(pubKey.base64EncodedString())</string>
                    
                """)
        } else {
            print("Generating a new signing key. This may take a moment, depending on your machine.")
            
            let (pubKey, privKey) = generateKeyPair()
            storeKeyPair(publicEdKey: pubKey, privateEdKey: privKey)
            
            printNewPublicKeyUsage(pubKey)
        }
    }
}

// Dispatch to a function because `@main` isn't stable yet at the time of this writing and top-level code is finicky.
entryPoint()
