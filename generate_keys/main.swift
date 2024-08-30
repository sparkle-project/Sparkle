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

private func commonKeychainItemAttributes(account: String) -> [String: Any] {
    /// Attributes used for both adding a new item and matching an existing one.
    return [
        /// The type of the item (a generic password).
        kSecClass        as String: kSecClassGenericPassword as String,
        
        /// The service string for the item (the Sparkle homepage URL).
        kSecAttrService  as String: "https://sparkle-project.org",
        
        /// The account name for the item (in this case, the key type).
        kSecAttrAccount  as String: account,
        
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

func findSecret(account: String) -> Data? {
    var item: CFTypeRef?
    let res = SecItemCopyMatching(commonKeychainItemAttributes(account: account).merging([
        /// Return a matched item's value as a CFData object.
        kSecReturnData as String: kCFBooleanTrue!,
    ], uniquingKeysWith: { $1 }) as CFDictionary, &item)
    
    switch res {
        case errSecSuccess:
            if let secret = (item as? Data).flatMap({ Data(base64Encoded: $0) }) {
                return secret
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

func generatePublicKeyAndSeed() -> (publicEdKey: Data, seed: Data) {
    var seed = Array<UInt8>(repeating: 0, count: 32)
    var publicEdKey = Array<UInt8>(repeating: 0, count: 32)
    var privateEdKey = Array<UInt8>(repeating: 0, count: 64)

    guard ed25519_create_seed(&seed) == 0 else {
        failure("Unable to initialize random seed. Try restarting your computer.")
    }
    ed25519_create_keypair(&publicEdKey, &privateEdKey, seed)
    
    return (Data(publicEdKey), Data(seed))
}

func storeSecret(account: String, publicEdKey: Data, secret: Data) {
    let query = commonKeychainItemAttributes(account: account).merging([
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
        kSecValueData       as String: secret.base64EncodedData() as CFData
    
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

struct GenerateKeys: ParsableCommand {
    @Option(help: ArgumentHelp("The account name to use when generating or looking up keys from your keychain. If this is not specified, a default global account is used instead. We recommend using different accounts for different organizations."))
    var account: String = "ed25519"
    
    @Flag(name: .customShort("p"), help: ArgumentHelp("Looks up and just prints the existing public key stored in the Keychain."))
    var lookUpPublicKey: Bool = false
    
    @Option(name: .customShort("x"), help: ArgumentHelp("Exports your private key from your login keychain and writes it to private-key-file. Note the contents of this sensitive exported file are the same as the password to the \"\(PRIVATE_KEY_LABEL)\" item in your keychain. For advanced usage if the private key is generated in the new format (i.e. the key file after base64 decoding is 32 bytes), then the exported key file is the base64 encoding of the private seed. The seed can be used to create the private/public keypair with other tools that support EdDSA signing.", valueName: "private-key-file"))
    var exportedPrivateKeyFile: String?
    
    @Option(name: .customShort("f"), help: ArgumentHelp("Imports the private key from private-key-file into your keychain instead of generating a new key. This file has likely been exported via -x option from another machine. Any existing \"\(PRIVATE_KEY_LABEL)\" items listed in Keychain Access may need to be removed manually first before proceeding.", valueName: "private-key-file"))
    var importedPrivateKeyFile: String?
    
    static var configuration: CommandConfiguration = CommandConfiguration(
        abstract: "Generate public & private keys for signing Sparkle based app updates.",
        discussion: """
        This tool generates a public & private keys and uses the macOS Keychain to store
        the private key for signing app updates which will be distributed via Sparkle.
        This key will be associated with your user account.
        
        Note: You only need one signing key, no matter how many apps you embed Sparkle in.
        
        The keychain may ask permission for this tool to access an existing key, if one
        exists, or for permission to save the new key. You must allow access in order to
        successfully proceed.
        
        In the default mode ran without any arguments, the public key and how it should be used
        in your application's Info.plist will be printed. If a private key was already generated in your Keychain,
        that key will be used and not overridden.
        
        You may additionally use options to only look up the existing public key for automation (-p),
        export the private key from your Keychain to a file for transferring the key (-x), or
        import the private key into your Keychain from a file (-f).
        """)
    
    func validate() throws {
        if lookUpPublicKey {
            guard exportedPrivateKeyFile == nil && importedPrivateKeyFile == nil else {
                throw ValidationError("-p option cannot be provided together with -x or -f.")
            }
        } else {
            guard exportedPrivateKeyFile == nil || importedPrivateKeyFile == nil else {
                throw ValidationError("Both -x and -f options cannot be provided together.")
            }
        }
    }
    
    func run() throws {
        if lookUpPublicKey {
            /// Lookup mode - print just the pubkey and exit
            if let secret = findSecret(account: account) {
                guard let (_, pubKey) = decodePrivateAndPublicKeys(secret: secret) else {
                    failure("Stored private key must be 32 or 96 bytes (for the older format) decoded. Instead it is \(secret.count) bytes decoded.")
                }
                print(pubKey.base64EncodedString())
            } else {
                failure("No existing signing key found!")
            }
        } else if let exportedPrivateKeyFile = exportedPrivateKeyFile {
            /// Export mode - export the key-pair file from the user's keychain
            let exportURL = URL(fileURLWithPath: exportedPrivateKeyFile)
            if let reachable = try? exportURL.checkResourceIsReachable(), reachable {
                failure("private-key-file already exists: \(exportURL.path)")
            }
            
            guard let secret = findSecret(account: account) else {
                failure("No existing signing key found!")
            }
            
            do {
                try secret.base64EncodedString().write(to: exportURL, atomically: true, encoding: .utf8)
            } catch {
                failure("Failed to write exported file: \(error)")
            }
        } else if let importedPrivateKeyFile = importedPrivateKeyFile {
            /// Import mode - import the specified key-pair file
            let secretBase64File = importedPrivateKeyFile
            let secretBase64: String
            do {
                secretBase64 = try decodeSecretString(filePath: secretBase64File)
            } catch {
                failure("Failed to read private-key-file: \(error.localizedDescription)")
            }
            
            guard let secret = Data(base64Encoded: secretBase64, options: .init()) else {
                failure("Failed to decode base64 encoded key data from: \(secretBase64)")
            }
            
            guard let (_, publicKey) = decodePrivateAndPublicKeys(secret: secret) else {
                failure("Imported key must be 32 or 96 bytes (for the older format) decoded. Instead it is \(secret.count) bytes decoded.")
            }
            
            print("Importing signing key..\n")
            
            storeSecret(account: account, publicEdKey: publicKey, secret: secret)
            
            printNewPublicKeyUsage(publicKey)
        } else {
            /// Default mode - find an existing public key and print its usage, or generate new keys
            if let secret = findSecret(account: account) {
                guard let (_, pubKey) = decodePrivateAndPublicKeys(secret: secret) else {
                    failure("Stored private key must be 32 or 96 bytes (for the older format) decoded. Instead it is \(secret.count) bytes decoded.")
                }
                
                print("""
                    A pre-existing signing key was found. This is how it should appear in your Info.plist:

                        <key>SUPublicEDKey</key>
                        <string>\(pubKey.base64EncodedString())</string>
                        
                    """)
            } else {
                print("Generating a new signing key. This may take a moment, depending on your machine.")
                
                let (pubKey, seed) = generatePublicKeyAndSeed()
                // New keys that are generated only store the seed as the secret
                // Old keys store private orlp/Ed25519 key + public key
                storeSecret(account: account, publicEdKey: pubKey, secret: seed)
                
                printNewPublicKeyUsage(pubKey)
            }
        }
    }
}

GenerateKeys.main()
