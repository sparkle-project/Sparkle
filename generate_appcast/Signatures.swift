//
//  Created by Kornel on 23/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
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

#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
func loadPrivateDSAKey(at privateKeyURL: URL) throws -> SecKey {
    let data = try Data(contentsOf: privateKeyURL)

    var cfitems: CFArray?
    var format = SecExternalFormat.formatOpenSSL
    var type = SecExternalItemType.itemTypePrivateKey

    let status = SecItemImport(data as CFData, nil, &format, &type, SecItemImportExportFlags(rawValue: UInt32(0)), nil, nil, &cfitems)
    if status != errSecSuccess || cfitems == nil {
        print("Private DSA key file", privateKeyURL.path, "exists, but it could not be read. SecItemImport error", status)
        throw NSError(domain: SUSparkleErrorDomain, code: Int(OSStatus(SUError.signatureError.rawValue)), userInfo: nil)
    }

    if format != SecExternalFormat.formatOpenSSL || type != SecExternalItemType.itemTypePrivateKey {
        throw makeError(code: .signatureError, "Not an OpensSSL private key \(format) \(type)")
    }

    return (cfitems! as NSArray)[0] as! SecKey
}

func loadPrivateDSAKey(named keyName: String, fromKeychainAt keychainURL: URL) throws -> SecKey {
    var keychain: SecKeychain?

    guard SecKeychainOpen(keychainURL.path, &keychain) == errSecSuccess, keychain != nil else {
        throw NSError(domain: SUSparkleErrorDomain, code: Int(OSStatus(SUError.signatureError.rawValue)), userInfo: nil)
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
        throw NSError(domain: SUSparkleErrorDomain, code: Int(OSStatus(SUError.signatureError.rawValue)), userInfo: nil)
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
        throw makeError(code: .signatureError, "SecTransformExecute returned non-data")
    }
    return resultData.base64EncodedString()
}
#endif

func edSignature(path: URL, publicEdKey: Data, privateEdKey: Data) throws -> String {
    assert(publicEdKey.count == 32)
    assert(privateEdKey.count == 64)
    let data = Array(try Data.init(contentsOf: path, options: .mappedIfSafe))
    var output = Array<UInt8>(repeating: 0, count: 64)
    let pubkey = Array(publicEdKey), privkey = Array(privateEdKey)
    
    ed25519_sign(&output, data, data.count, pubkey, privkey)
    return Data(output).base64EncodedString()
}
