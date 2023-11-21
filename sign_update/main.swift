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
    if res == errSecSuccess {
        guard let encoded = item as? Data else {
            print("ERROR! Unable to decode data from Keychain")
            throw ExitCode.failure
        }
        
        guard let keyPair = Data(base64Encoded: encoded) else {
            print("ERROR! Unable to decode data from Keychain as base64")
            throw ExitCode.failure
        }
        
        guard let (privateKey, publicKey) = decodePrivateAndPublicKeys(keyPair: keyPair) else {
            print("ERROR! Key pair data stored in keychain has \(keyPair.count) bytes which is invalid")
            throw ExitCode.failure
        }
        
        return (privateKey, publicKey)
    } else if res == errSecItemNotFound {
        print("ERROR! Signing key not found for account \(account). Please run generate_keys tool first or provide key with --ed-key-file <private_key_file>")
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

func findKeys(inFile keyPairFile: String) throws -> (Data, Data) {
    let keyPair: String
    if keyPairFile == "-" && !FileManager.default.fileExists(atPath: keyPairFile) {
        if let line = readLine(strippingNewline: true) {
            keyPair = line
        } else {
            print("ERROR! Unable to read EdDSA private key from standard input")
            throw ExitCode(1)
        }
    } else {
        keyPair = try String(contentsOfFile: keyPairFile)
    }
    return try findKeys(inString: keyPair, allowNewFormat: true)
}

func findKeys(inString keyPair: String, allowNewFormat: Bool) throws -> (Data, Data) {
    guard let keyPairData = Data(base64Encoded: keyPair.trimmingCharacters(in: .whitespacesAndNewlines), options: .init()) else {
        print("ERROR! Failed to decode base64 encoded key data from: \(keyPair)")
        throw ExitCode.failure
    }
    
    guard allowNewFormat || !keyPairUsesRegularSeed(keyPair: keyPairData) else {
        print("ERROR! Specifying private key as an argument is no longer supported.")
        throw ExitCode.failure
    }
    
    guard let (privateKey, publicKey) = decodePrivateAndPublicKeys(keyPair: keyPairData) else {
        print("ERROR! Imported key must be 64 bytes or 96 bytes (for the older format) decoded. Instead it is \(keyPairData.count) bytes decoded.")
        throw ExitCode.failure
    }
    
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
    static let programName = "sign_update"
    
    @Option(help: ArgumentHelp("The account name in your keychain associated with your private EdDSA (ed25519) key to use for signing the update."))
    var account: String = "ed25519"
    
    @Flag(help: ArgumentHelp("Verify that the update is signed correctly. If this is set, a second argument <verify-signature> denoting the signature must be passed after the <update-path>.", valueName: "verify"))
    var verify: Bool = false
    
    @Option(name: [.customShort("f"), .customLong("ed-key-file")], help: ArgumentHelp("Path to the file containing the private EdDSA (ed25519) key. '-' can be used to echo the EdDSA key from a 'secret' environment variable to the standard input stream. For example: echo \"$PRIVATE_KEY_SECRET\" | ./\(programName) --ed-key-file -", valueName: "private-key-file"))
    var privateKeyFile: String?
    
    @Flag(name: .customShort("p"), help: ArgumentHelp("Only prints the signature when signing an update."))
    var printOnlySignature: Bool = false
    
    @Argument(help: "The update archive, delta update, or package (pkg) to sign or verify.")
    var updatePath: String
    
    @Argument(help: "The signature to verify when --verify is passed.")
    var verifySignature: String?
    
    @Option(name: .customShort("s"), help: ArgumentHelp("(DEPRECATED): The private EdDSA (ed25519) key. Please use the Keychain, or pass the key as standard input when using --ed-key-file - instead. This option is no longer supported for newly generated keys. ", valueName: "private-key"))
    var privateKey: String?
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        abstract: "Sign or verify an update using your EdDSA (ed25519) keys.",
        discussion: "The EdDSA keys are automatically read from the Keychain if no <private-key-file> is specified.\n\nWhen signing, this tool will output an EdDSA signature and length attributes to use for your update's appcast item enclosure. You can use -p to only print the EdDSA signature for automation.")
    
    func validate() throws {
        guard privateKey == nil || privateKeyFile == nil else {
            throw ValidationError("Both --ed-key-file <private-key-file> and -s <private-key> options cannot be provided.")
        }
        
        guard !verify || verifySignature != nil else {
            throw ValidationError("<verify-signature> must be passed as a second argument after <update-path> if --verify is passed.")
        }
        
        guard !verify || !printOnlySignature else {
            throw ValidationError("Both --verify and -p options cannot be provided.")
        }
    }
    
    func run() throws {
        let (priv, pub): (Data, Data)
        
        if let privateKey = privateKey {
            fputs("Warning: The -s option for passing the private EdDSA key is insecure and deprecated. Please see its help usage for more information.\n", stderr)
            
            (priv, pub) = try findKeys(inString: privateKey, allowNewFormat: false)
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
            
            if printOnlySignature {
                print(sig)
            } else {
                print("sparkle:edSignature=\"\(sig)\" length=\"\(data.count)\"")
            }
        }
    }
}

SignUpdate.main()
