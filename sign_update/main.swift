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
        
        guard let secret = Data(base64Encoded: encoded) else {
            print("ERROR! Unable to decode data from Keychain as base64")
            throw ExitCode.failure
        }
        
        guard let (privateKey, publicKey) = decodePrivateAndPublicKeys(secret: secret) else {
            print("ERROR! Key pair data stored in keychain has \(secret.count) bytes which is invalid")
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

func findKeys(inFile secretFile: String) throws -> (Data, Data) {
    let secretString: String
    if secretFile == "-" && !FileManager.default.fileExists(atPath: secretFile) {
        if let line = readLine(strippingNewline: true) {
            secretString = line
        } else {
            print("ERROR! Unable to read EdDSA private key from standard input")
            throw ExitCode(1)
        }
    } else {
        secretString = try decodeSecretString(filePath: secretFile)
    }
    return try findKeys(inString: secretString, allowNewFormat: true)
}

func findKeys(inString secretBase64String: String, allowNewFormat: Bool) throws -> (Data, Data) {
    guard let secret = Data(base64Encoded: secretBase64String, options: .init()) else {
        print("ERROR! Failed to decode base64 encoded key data from: \(secretBase64String)")
        throw ExitCode.failure
    }
    
    guard allowNewFormat || !secretUsesRegularSeed(secret: secret) else {
        print("ERROR! Specifying private key as an argument is no longer supported.")
        throw ExitCode.failure
    }
    
    guard let (privateKey, publicKey) = decodePrivateAndPublicKeys(secret: secret) else {
        print("ERROR! Imported key must be 64 bytes or 96 bytes (for the older format) decoded. Instead it is \(secret.count) bytes decoded.")
        throw ExitCode.failure
    }
    
    return (privateKey, publicKey)
}

struct SignUpdate: ParsableCommand {
    static let programName = "sign_update"
    
    @Option(help: ArgumentHelp("The account name in your keychain associated with your private keys to use for signing."))
    var account: String = "ed25519"
    
    @Flag(help: ArgumentHelp("Verify that the file is signed correctly. If this is set, a second argument <verify-signature> denoting the signature must be passed after the <update-path>.", valueName: "verify"))
    var verify: Bool = false
    
    @Option(name: [.customShort("f"), .customLong("ed-key-file")], help: ArgumentHelp("Path to the file containing the private EdDSA (ed25519) key. '-' can be used to echo the EdDSA key from a 'secret' environment variable to the standard input stream. For example: echo \"$PRIVATE_KEY_SECRET\" | ./\(programName) --ed-key-file -", valueName: "private-key-file"))
    var privateKeyFile: String?
    
    @Flag(name: .customShort("p"), help: ArgumentHelp("Only prints the signature when signing a file without extra metadata. For signing XML files, nothing will be printed because the signature is embedded inside the file."))
    var printOnlySignature: Bool = false
    
    @Argument(help: "The update archive, delta update, package (pkg), release notes file, or update feed (xml) to sign or verify. If the file is a update feed (xml), the file will be modified to include the generated signature. If the file is a release notes file, the file may also be updated to include a warning that it is signed (unless --disable-signing-warning is specified).")
    var filePath: String
    
    @Flag(name: .long, help: ArgumentHelp("Disables adding a warning to signed appcast and release note files explaining that further modifications will require re-signing them. This flag has no effect if the files already have a signing warning embedded."))
    var disableSigningWarning: Bool = false
    
    @Argument(help: "The signature to verify when --verify is passed. Don't pass this option for verifying appcast XML feeds, which already have a signature embedded.")
    var verifySignature: String?
    
    @Option(name: .customShort("s"), help: ArgumentHelp("(DEPRECATED): The private EdDSA (ed25519) key. Please use the Keychain, or pass the key as standard input when using --ed-key-file - instead. This option is no longer supported for newly generated keys.", valueName: "private-key"))
    var privateKey: String?
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        abstract: "Sign or verify an update file using your signing keys.",
        discussion:
            """
            sign_update can be used to sign or verify update archives, delta updates, pkg updates, appcast feeds, and release note files.
            
            The signing keys are automatically read from the Keychain if no <private-key-file> is specified.
            
            For signing update archives, sign_update will output an EdDSA signature and length attributes to use for your update's appcast item enclosure.
            
            For signing release note files, sign_update will output an EdDSA signature and length attributes to use for your update's appcast releaseNotesLink. Additionally, the release notes file may be modified to include a warning about making future modifications to the file (unless --disable-signing-warning is specified).
            
            For signing appcast feeds, sign_update will embed the signature inside the XML file and include a warning about making future modifications to the file (unless --disable-signing-warning is specified).
            
            For signing files, you can use -p to only print the EdDSA signature for automation.
            """)
    
    private var filePathIsFeed: Bool {
        return filePath.hasSuffix(".xml") || filePath.hasSuffix(".XML")
    }
    
    private var filePathIsHTMLReleaseNotes: Bool {
        return filePath.hasSuffix(".html") ||
               filePath.hasSuffix(".htm")
    }
    
    private var filePathIsMarkdownReleaseNotes: Bool {
        return filePath.hasSuffix(".md") ||
               filePath.hasSuffix(".markdown")
    }
    
    private var filePathIsReleaseNotes: Bool {
        return filePath.hasSuffix(".txt") ||
               self.filePathIsMarkdownReleaseNotes ||
               self.filePathIsHTMLReleaseNotes
    }
    
    func validate() throws {
        guard privateKey == nil || privateKeyFile == nil else {
            throw ValidationError("Both --ed-key-file <private-key-file> and -s <private-key> options cannot be provided.")
        }
        
        guard !verify || verifySignature != nil || self.filePathIsFeed else {
            throw ValidationError("<verify-signature> must be passed as a second argument after <file-path> if --verify is passed.")
        }
        
        guard !self.filePathIsFeed || verifySignature == nil else {
            throw ValidationError("<verify-signature> must not be passed for signing appcast feeds, which already have the signature embedded.")
        }
        
        guard !verify || !printOnlySignature else {
            throw ValidationError("Both --verify and -p options cannot be provided.")
        }
    }
    
    func run() throws {
        let (priv, pub): (Data, Data)
        
        if let privateKey = privateKey?.trimmingCharacters(in: .whitespacesAndNewlines) {
            fputs("Warning: The -s option for passing the private EdDSA key is insecure and deprecated. Please see its help usage for more information.\n", stderr)
            
            (priv, pub) = try findKeys(inString: privateKey, allowNewFormat: false)
        } else if let privateKeyFile = privateKeyFile {
            (priv, pub) = try findKeys(inFile: privateKeyFile)
        } else {
            (priv, pub) = try findKeysInKeychain(account: account)
        }
        
        let fileURL = URL(fileURLWithPath: filePath, isDirectory: false).resolvingSymlinksInPath()
    
        let data = try Data.init(contentsOf: fileURL, options: .mappedIfSafe)
        if verify {
            // Verify the signature
            
            let dataToVerify: Data
            let base64Signature: String
            let expectedContentLength: UInt64
            if let verifySignature {
                base64Signature = verifySignature
                dataToVerify = data
                expectedContentLength = UInt64(data.count)
            } else {
                assert(self.filePathIsFeed)
                
                var processedBase64Signature: NSString? = nil
                var processedExpectedContentLength: UInt64 = 0
                dataToVerify = SPUExtractAppcastContent(data, &processedBase64Signature, &processedExpectedContentLength)
                
                expectedContentLength = processedExpectedContentLength
                
                guard let processedBase64Signature else {
                    print("Error: failed to extract signature from appcast. Is the appcast signed?")
                    throw ExitCode.failure
                }
                
                base64Signature = processedBase64Signature as String
            }
            
            guard let signatureData = Data(base64Encoded: base64Signature, options: .ignoreUnknownCharacters) else {
                print("Error: failed to decode base64 signature: \(base64Signature)")
                throw ExitCode.failure
            }
            
            let signatureBytes = Array(signatureData)
            guard signatureBytes.count == 64 else {
                print("Error: signature passed in has an invalid byte count.")
                throw ExitCode.failure
            }
            
            let dataBytesToVerify = Array(dataToVerify)
            let publicKeyBytes = Array(pub)
            
            if ed25519_verify(signatureBytes, dataBytesToVerify, dataBytesToVerify.count, publicKeyBytes) == 0 {
                print("Error: failed to pass signing verification.")
                let dataBytesCount = UInt64(dataBytesToVerify.count)
                if expectedContentLength != dataBytesCount {
                    print("\(expectedContentLength) bytes were expected to be signed, but actually read \(dataBytesCount) bytes.")
                }
                throw ExitCode.failure
            }
        } else {
            // Sign the update
            if self.filePathIsFeed {
                let contentData = SPUExtractAppcastContent(data, nil, nil)
                
                let dataToSign: Data = disableSigningWarning ? contentData : addSignWarningToAppcast(data: contentData)
                let addedSignWarningToAppcast = (contentData.count != dataToSign.count)
                let signedData = try signAppcast(data: dataToSign, publicEdKey: pub, privateEdKey: priv)
                try signedData.write(to: fileURL, options: .atomic)
                
                if !printOnlySignature {
                    if !addedSignWarningToAppcast {
                        print("<!-- Updated signature inside \(fileURL.lastPathComponent) -->")
                    } else {
                        print("<!-- Updated signature inside \(fileURL.lastPathComponent) and added warning for making further modifications. -->")
                    }
                }
            } else {
                let signedData: Data
                let updatedSigningWarningInReleaseNotes: Bool
                
                if disableSigningWarning || (!self.filePathIsHTMLReleaseNotes && !self.filePathIsMarkdownReleaseNotes) {
                    signedData = data
                    updatedSigningWarningInReleaseNotes = false
                } else {
                    if let updatedDataForSigning = updateHTMLCommentSigningWarningInReleaseNotes(data: data) {
                        do {
                            try updatedDataForSigning.write(to: fileURL, options: .atomic)
                            signedData = updatedDataForSigning
                            updatedSigningWarningInReleaseNotes = true
                        } catch {
                            // Fallback to original data if the release notes is not updatable
                            signedData = data
                            updatedSigningWarningInReleaseNotes = false
                        }
                    } else {
                        signedData = data
                        updatedSigningWarningInReleaseNotes = false
                    }
                }
                
                let sig = edSignature(data: signedData, publicEdKey: pub, privateEdKey: priv)
                
                if printOnlySignature {
                    print(sig)
                } else {
                    if self.filePathIsReleaseNotes {
                        if updatedSigningWarningInReleaseNotes {
                            print("<!-- Updated \(fileURL.lastPathComponent) by adding warning for making further modifications. -->")
                        }
                        print("sparkle:edSignature=\"\(sig)\" sparkle:length=\"\(signedData.count)\"")
                    } else {
                        print("sparkle:edSignature=\"\(sig)\" length=\"\(signedData.count)\"")
                    }
                }
            }
        }
    }
}

SignUpdate.main()
