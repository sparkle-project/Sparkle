//
//  main.swift
//  sign_update
//
//  Created by Kornel on 16/09/2018.
//  Copyright © 2018 Sparkle Project. All rights reserved.
//

import Foundation
import Security
import ArgumentParser

func findKeysInKeychain(account: String) throws -> (Data, Data) {
    var item: CFTypeRef?
    let res = SecItemCopyMatching([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "https://sparkle-project.org",
        kSecAttrAccount as String: account,
        kSecAttrProtocol as String: kSecAttrProtocolSSH,
        kSecReturnData as String: kCFBooleanTrue!,
        ] as CFDictionary, &item)
    if res == errSecSuccess, let encoded = item as? Data, let keys = Data(base64Encoded: encoded) {
        return (keys[0..<64], keys[64..<(64+32)])
    } else if res == errSecItemNotFound {
        print("ERROR! Signing key not found for account \(account). Please run generate_keys tool first or provide key with -f <private_key_file> or -s <private_key> parameter.")
    } else if res == errSecAuthFailed {
        print("ERROR! Access denied. Can't get keys from the keychain.")
        print("Go to Keychain Access.app, lock the login keychain, then unlock it again.")
    } else if res == errSecUserCanceled {
        print("ABORTED! You've cancelled the request to read the key from the Keychain. Please run the tool again.")
    } else if res == errSecInteractionNotAllowed {
        print("ERROR! The operating system has blocked access to the Keychain.")
    } else {
        print("ERROR! Unable to access required key in the Keychain: \(res) (you can look it up at osstatus.com)")
    }
    throw ExitCode.failure
}

func findKeys(inFile privateAndPublicBase64KeyFile: String) throws -> (Data, Data) {
    let privateAndPublicBase64Key = try String(contentsOfFile: privateAndPublicBase64KeyFile)
    return try findKeys(inString: privateAndPublicBase64Key)
}

func findKeys(inString privateAndPublicBase64Key: String) throws -> (Data, Data) {
    guard let privateAndPublicKey = Data(base64Encoded: privateAndPublicBase64Key.trimmingCharacters(in: .whitespacesAndNewlines), options: .init()) else {
        print("ERROR! Failed to decode base64 encoded key data from: \(privateAndPublicBase64Key)")
        throw ExitCode.failure
    }
    
    guard privateAndPublicKey.count == 64 + 32 else {
        print("ERROR! Imported key must be 96 bytes decoded. Instead it is \(privateAndPublicKey.count) bytes decoded.")
        throw ExitCode.failure
    }
    
    let publicKey = privateAndPublicKey[64...]
    let privateKey = privateAndPublicKey[0..<64]
    
    return (privateKey, publicKey)
}

func edSignature(data: Data, publicEdKey: Data, privateEdKey: Data) -> String {
    assert(publicEdKey.count == 32)
    assert(privateEdKey.count == 64)
    let data = Array(data)
    var output = Array<UInt8>(repeating: 0, count: 64)
    let pubkey = Array(publicEdKey), privkey = Array(privateEdKey)
    
    ed25519_sign(&output, data, data.count, pubkey, privkey)
    return Data(output).base64EncodedString()
}

struct SignUpdate: ParsableCommand {
    @Option(help: ArgumentHelp("The account name in your keychain associated with your private EdDSA (ed25519) key to use for signing the update."))
    var account: String = "ed25519"
    
    @Flag(help: ArgumentHelp("Verify that the update is signed correctly. If this is set, a second argument <verify-signature> denoting the signature must be passed after the <update-path>.", valueName: "verify"))
    var verify: Bool = false
    
    @Option(name: .customShort("s"), help: ArgumentHelp("The private EdDSA (ed25519) key.", valueName: "private-key"))
    var privateKey: String?
    
    @Option(name: .customShort("f"), help: ArgumentHelp("Path to the file containing the private EdDSA (ed25519) key.", valueName: "private-key-file"))
    var privateKeyFile: String?
    
    @Argument(help: "The update archive, delta update, or package (pkg) to sign or verify.")
    var updatePath: String
    
    @Argument(help: "The signature to verify when --verify is passed.")
    var verifySignature: String?
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        abstract: "Sign or verify an update using your EdDSA (ed25519) keys.",
        discussion: "The EdDSA keys are automatically read from the Keychain if no <private-key> or <private-key-file> is specified.\n\nWhen signing, this tool will output an EdDSA signature and length attributes to use for your update's appcast item enclosure.")
    
    func validate() throws {
        guard privateKey == nil || privateKeyFile == nil else {
            throw ValidationError("Both -s <private-key> and -f <private-key-file> options cannot be provided.")
        }
        
        guard !verify || verifySignature != nil else {
            throw ValidationError("<verify-signature> must be passed as a second argument after <update-path> if --verify is passed.")
        }
    }
    
    func run() throws {
        let (priv, pub): (Data, Data)
        
        if let privateKey = privateKey {
            (priv, pub) = try findKeys(inString: privateKey)
        } else if let privateKeyFile = privateKeyFile {
            (priv, pub) = try findKeys(inFile: privateKeyFile)
        } else {
            (priv, pub) = try findKeysInKeychain(account: account)
        }
    
        let data = try Data.init(contentsOf: URL.init(fileURLWithPath: updatePath), options: .mappedIfSafe)
        if verify {
            // Verify the signature
            guard let verifySignature = verifySignature else {
                print("Error: failed to unwrap verifySignature, which is unexpected")
                throw ExitCode.failure
            }
            
            guard let signatureData = Data(base64Encoded: verifySignature, options: .ignoreUnknownCharacters) else {
                print("Error: failed to decode base64 signature: \(verifySignature)")
                throw ExitCode.failure
            }
            
            let signatureBytes = Array(signatureData)
            guard signatureBytes.count == 64 else {
                print("Error: signature passed in has an invalid byte count.")
                throw ExitCode.failure
            }
            
            let dataBytes = Array(data)
            let publicKeyBytes = Array(pub)
            
            if ed25519_verify(signatureBytes, dataBytes, data.count, publicKeyBytes) == 0 {
                print("Error: failed to pass signing verification.")
                throw ExitCode.failure
            }
        } else {
            // Sign the update
            let sig = edSignature(data: data, publicEdKey: pub, privateEdKey: priv)
            print("sparkle:edSignature=\"\(sig)\" length=\"\(data.count)\"")
        }
    }
}

SignUpdate.main()
