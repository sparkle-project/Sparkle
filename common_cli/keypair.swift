//
//  keypair.swift
//  Sparkle
//
//  Created on 11/19/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

import Foundation

func keyPairUsesRegularSeed(keyPair: Data) -> Bool {
    return (keyPair.count == 32 + 32)
}

func keyPairUsesOldHashedSeed(keyPair: Data) -> Bool {
    return (keyPair.count == 64 + 32)
}

// Private data is the data we store in the keychain
// For newer generated keys, privateData is the private seed
// For older generated keys, privateData is the full private Ed25519 key
// If the keyPair is of invalid length, this returns nil
func decodePrivateDataAndPublicKey(keyPair: Data) -> (privateData: Data, publicKey: Data)? {
    let publicKey: Data
    let privateData: Data
    if keyPairUsesOldHashedSeed(keyPair: keyPair) {
        // Old format without seed
        publicKey = keyPair[64...]
        privateData = keyPair[0..<64]
    } else if keyPairUsesRegularSeed(keyPair: keyPair) {
        publicKey = keyPair[32...]
        privateData = keyPair[0..<32]
    } else {
        return nil
    }
    
    return (privateData, publicKey)
}

func decodePrivateAndPublicKeys(keyPair: Data) -> (privateKey: Data, publicKey: Data)? {
    guard let (privateData, publicKey) = decodePrivateDataAndPublicKey(keyPair: keyPair) else {
        return nil
    }
    
    if keyPairUsesRegularSeed(keyPair: keyPair) {
        // For newly generated keys, we need to convert the private seed
        // to the private Ed25519 key
        let seed = privateData
        var privateEdKey = Array<UInt8>(repeating: 0, count: 64)
        seed.withUnsafeBytes { bytes in
            let buffer: UnsafePointer<UInt8> = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)

            ed25519_convert_ref10_private_key(&privateEdKey, buffer)
        }
        
        return (Data(privateEdKey), publicKey)
    } else {
        return (privateData, publicKey)
    }
}

func decodePublicKey(keyPair: Data) -> Data? {
    guard let (_, publicKey) = decodePrivateDataAndPublicKey(keyPair: keyPair) else {
        return nil
    }
    return publicKey
}
