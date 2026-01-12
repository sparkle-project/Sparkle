//
//  signing.swift
//  Sparkle
//
//  Created on 12/26/25.
//  Copyright © 2025 Sparkle Project. All rights reserved.
//

import Foundation

struct PrivateKeys {
    var privateDSAKey: SecKey?
    var privateEdKey: Data?
    var publicEdKey: Data?

    init(privateDSAKey: SecKey?, privateEdKey: Data?, publicEdKey: Data?) {
        self.privateDSAKey = privateDSAKey
        self.privateEdKey = privateEdKey
        self.publicEdKey = publicEdKey
    }
}

enum SigningError: Error {
    case failedToDecodeSigningBlockAsUTF8
}

// All of these are for legacy DSA related errors
enum DSAError: Error {
    case invalidOpenSSLFormat
    case invalidSecTransformData
    case secKeychainOpenFailure
    case secItemImportFailure
    case secItemCopyFailure
}

// Adds a XML comment at the begining warning the developer about making future modifications to this signed appcast.
func addSignWarningToAppcast(data inputData: Data) -> Data {
    let xmlData: Data
    do {
        let signWarningPrefix = " sparkle-sign-warning:"
        let signWarningMessage = "\nIMPORTANT: This file was signed by Sparkle. Any modifications to this file requires re-signing this file with generate_appcast or sign_update! The signed signature will be embedded at the end of this file.\n"
        
        let readAndWriteOptions: XMLNode.Options = [
            XMLNode.Options.nodeLoadExternalEntitiesNever,
            XMLNode.Options.nodePreserveCDATA,
            XMLNode.Options.nodePreserveWhitespace,
        ]
        
        do {
            let document = try XMLDocument(data: inputData, options: readAndWriteOptions)
            
            var foundSignWarningComment: Bool = false
            if let documentChildren = document.children {
                for child in documentChildren {
                    if child.kind == .comment, let commentValue = child.stringValue, commentValue.hasPrefix(signWarningPrefix) {
                        foundSignWarningComment = true
                        break
                    }
                }
            }
            
            if !foundSignWarningComment {
                let newSigningWarningMessage = "\(signWarningPrefix)\(signWarningMessage)"
                
                let newCommentNode = XMLNode(kind: .comment)
                newCommentNode.stringValue = newSigningWarningMessage
                document.insertChild(newCommentNode, at: 0)
                
                xmlData = document.xmlData(options: readAndWriteOptions)
            } else {
                xmlData = inputData
            }
        } catch {
            print("Error: failed to parse XML data: \(error)")
            xmlData = inputData
        }
    }
    
    return xmlData
}

// Sign the contents of the XML data, and append the signing block (containing the signature / other info)
// to the end of the appcast data.
// The input data should have the signing block already stripped (use SPUExtractAppcastContent()
func signAppcast(data contentData: Data, publicEdKey: Data, privateEdKey: Data) throws -> Data {
    let base64Signature = edSignature(data: contentData, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
    
    let signingBlock = "<!-- sparkle-signatures:\nedSignature: \(base64Signature)\nlength: \(contentData.count)\n-->\n"
    
    guard let signingBlockData = signingBlock.data(using: .utf8) else {
        // Extremely unlikely to occur
        throw SigningError.failedToDecodeSigningBlockAsUTF8
    }
    
    var signedData = contentData
    signedData.append(signingBlockData)
    
    return signedData
}

// This inserts a HTML comment in the beginning of the data warning the developer
// that future modifications to this file will require it to be re-signed
func updateHTMLCommentSigningWarningInReleaseNotes(data: Data) -> Data? {
    let modificationWarningPrefix = "<!-- sparkle-sign-warning:"
    
    // If there's already a warning, it's not worth it to update the warning message again
    // (even if it's slightly different / out of date).
    guard data.range(of: Data(modificationWarningPrefix.utf8)) == nil else {
        return nil
    }
    
    let modificationWarningSuffix = "-->\n"
    
    let modificationWarningMessage = "\(modificationWarningPrefix)\nIMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.\n\(modificationWarningSuffix)"
    
    var dataToSign = data
    dataToSign.insert(contentsOf: Data(modificationWarningMessage.utf8), at: dataToSign.startIndex)

    return dataToSign
}

#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
func loadPrivateDSAKey(at privateKeyURL: URL) throws -> SecKey {
    let data = try Data(contentsOf: privateKeyURL)

    var cfitems: CFArray?
    var format = SecExternalFormat.formatOpenSSL
    var type = SecExternalItemType.itemTypePrivateKey

    let status = SecItemImport(data as CFData, nil, &format, &type, SecItemImportExportFlags(rawValue: UInt32(0)), nil, nil, &cfitems)
    if status != errSecSuccess || cfitems == nil {
        print("Private DSA key file", privateKeyURL.path, "exists, but it could not be read. SecItemImport error", status)
        throw DSAError.secItemImportFailure
    }

    if format != SecExternalFormat.formatOpenSSL || type != SecExternalItemType.itemTypePrivateKey {
        print("Not an OpensSSL private key \(format) \(type)")
        throw DSAError.invalidOpenSSLFormat
    }

    return (cfitems! as NSArray)[0] as! SecKey
}

func loadPrivateDSAKey(named keyName: String, fromKeychainAt keychainURL: URL) throws -> SecKey {
    var keychain: SecKeychain?

    guard SecKeychainOpen(keychainURL.path, &keychain) == errSecSuccess, keychain != nil else {
        throw DSAError.secKeychainOpenFailure
    }

    let query: [CFString: CFTypeRef] = [
        kSecClass: kSecClassKey,
        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        kSecAttrLabel: keyName as CFString,
        kSecMatchLimit: kSecMatchLimitOne,
        kSecUseKeychain: keychain!,
        kSecReturnRef: kCFBooleanTrue,
    ]

    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, item != nil else {
        throw DSAError.secItemCopyFailure
    }

    return item! as! SecKey
}

func dsaSignature(path: URL, privateDSAKey: SecKey) throws -> String {

    var error: Unmanaged<CFError>?

    let stream = InputStream(fileAtPath: path.path)!
    let dataReadTransform = SecTransformCreateReadTransformWithReadStream(stream)

    let dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, 20, nil)
    guard let dataSignTransform = SecSignTransformCreate(privateDSAKey, &error) else {
        print("can't use the key")
        throw error!.takeRetainedValue()
    }

    let group = SecTransformCreateGroupTransform()
    SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error)
    if error != nil {
        throw error!.takeRetainedValue()
    }

    SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataSignTransform, kSecTransformInputAttributeName, group, &error)
    if error != nil {
        throw error!.takeRetainedValue()
    }

    let result = SecTransformExecute(group, &error)
    if error != nil {
        throw error!.takeRetainedValue()
    }
    guard let resultData = result as? Data else {
        throw DSAError.invalidSecTransformData
    }
    return resultData.base64EncodedString()
}
#endif

func edSignature(data: Data, publicEdKey: Data, privateEdKey: Data) -> String {
    assert(publicEdKey.count == 32)
    assert(privateEdKey.count == 64)
    let data = Array(data)
    var output = Array<UInt8>(repeating: 0, count: 64)
    let pubkey = Array(publicEdKey), privkey = Array(privateEdKey)
    
    ed25519_sign(&output, data, data.count, pubkey, privkey)
    return Data(output).base64EncodedString()
}

func edSignature(path: URL, publicEdKey: Data, privateEdKey: Data) throws -> String {
    let data = try Data(contentsOf: path, options: .mappedIfSafe)
    return edSignature(data: data, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
}
