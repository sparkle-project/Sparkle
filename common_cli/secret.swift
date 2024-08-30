//
//  secret.swift
//  Sparkle
//
//  Created on 11/19/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

import Foundation

func secretUsesRegularSeed(secret: Data) -> Bool {
    return (secret.count == 32)
}

func secretUsesOldHashedSeed(secret: Data) -> Bool {
    return (secret.count == 64 + 32)
}

// Secret is the data we store in the keychain
// For newer generated keys, secret is the private seed
// For older generated keys, secret is the private orlp/Ed25519 key concatenated with the public key
// If the secret is of invalid length, this returns nil
func decodePrivateAndPublicKeys(secret: Data) -> (privateKey: Data, publicKey: Data)? {
    let privateKey: Data
    let publicKey: Data
    
    if secretUsesRegularSeed(secret: secret) {
        let seed = secret
        
        var privateEdKey = Array<UInt8>(repeating: 0, count: 64)
        var publicEdKey = Array<UInt8>(repeating: 0, count: 32)
        seed.withUnsafeBytes { seedBytes in
            let seedBuffer: UnsafePointer<UInt8> = seedBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            ed25519_create_keypair(&publicEdKey, &privateEdKey, seedBuffer)
        }
        
        privateKey = Data(privateEdKey)
        publicKey = Data(publicEdKey)
    } else if secretUsesOldHashedSeed(secret: secret) {
        privateKey = secret[0..<64]
        publicKey = secret[64...]
    } else {
        return nil
    }
    
    return (privateKey, publicKey)
}

enum DecodeSecretStringError : LocalizedError {
    case unableToReadData
    case unableToDecodeDataAsUTF8String
    
    public var errorDescription: String? {
        switch self {
        case .unableToReadData:
            return "Unable to read EdDSA private key data"
        case .unableToDecodeDataAsUTF8String:
            return "Unable to read EdDSA private key data as UTF-8 string"
        }
    }
}

// Reads secret base64 string from a file
func decodeSecretString(filePath: String) throws -> String {
    let privateKeyString: String
    if #available(macOS 10.15.4, *) {
        // Prefer to use FileHandle which supports process substitution:
        // https://github.com/sparkle-project/Sparkle/issues/2605
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        
        guard let data = try fileHandle.readToEnd() else {
            throw DecodeSecretStringError.unableToReadData
        }
        
        guard let decodedPrivateKeyString = String(data: data, encoding: .utf8) else {
            throw DecodeSecretStringError.unableToDecodeDataAsUTF8String
        }
        
        privateKeyString = decodedPrivateKeyString
    } else {
        privateKeyString = try String(contentsOf: URL(fileURLWithPath: filePath))
    }
    
    return privateKeyString.trimmingCharacters(in: .whitespacesAndNewlines)
}
