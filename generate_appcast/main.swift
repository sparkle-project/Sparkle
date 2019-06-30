//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

var verbose = false;

func printUsage() {
    let command = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent;
    print("Generate appcast from a directory of Sparkle update archives\n",
        "Usage:\n",
        "      \(command) <directory with update files>\n",
        " e.g. \(command) ./my-app-release-zipfiles/\n",
        "\nOR for old apps that have a DSA keys (deprecated):\n",
        "      \(command) <private DSA key path> <directory with update files>\n",
        " e.g. \(command) dsa_priv.pem archives/\n",
        "\n",
        "Appcast files and deltas will be written to the archives directory.\n",
        "Note that pkg-based updates are not supported.\n"
    )
}

func loadPrivateKeys(_ privateDSAKey: SecKey?) -> PrivateKeys {
    var privateEdKey: Data?;
    var publicEdKey: Data?;
    var item: CFTypeRef?;
    let res = SecItemCopyMatching([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "https://sparkle-project.org",
        kSecAttrAccount as String: "ed25519",
        kSecAttrProtocol as String: kSecAttrProtocolSSH,
        kSecReturnData as String: kCFBooleanTrue,
        ] as CFDictionary, &item);
    if res == errSecSuccess, let encoded = item as? Data, let keys = Data(base64Encoded: encoded) {
        privateEdKey = keys[0..<64];
        publicEdKey = keys[64...];
    } else {
        print("Warning: Private key not found in the Keychain (\(res)). Please run the generate_keys tool");
    }
    return PrivateKeys(privateDSAKey: privateDSAKey, privateEdKey: privateEdKey, publicEdKey: publicEdKey);
}

func main() {
    let args = CommandLine.arguments;
    if args.count < 2 {
        printUsage()
        exit(1)
    }
    
    var privateDSAKey: SecKey? = nil;

    // this was typical usage for DSA keys
    if args.count == 3 || (args.count == 4 && args[1] == "-f") {
        // private key specified by filename
        let privateKeyURL = URL(fileURLWithPath: args.count == 3 ? args[1] : args[2])
        
        do {
            privateDSAKey = try loadPrivateDSAKey(at: privateKeyURL)
        } catch {
            print("Unable to load DSA private key from", privateKeyURL.path, "\n", error)
            exit(1)
        }
    }
    // this is legacy for DSA keychain; probably very rarely used
    else if args.count == 6 && (args[1] == "-n" || args[1] == "-k") {
        // private key specified by keychain + key name
        let keyName: String
        let keychainURL: URL
        
        if args[1] == "-n" {
            if args[3] != "-k" {
                printUsage()
                exit(1)
            }
            
            keyName = args[2]
            keychainURL = URL(fileURLWithPath: args[4])
        }
        else {
            if args[3] != "-n" {
                printUsage()
                exit(1)
            }
            
            keyName = args[4]
            keychainURL = URL(fileURLWithPath: args[2])
        }

        do {
            privateDSAKey = try loadPrivateDSAKey(named: keyName, fromKeychainAt: keychainURL)
        } catch {
            print("Unable to load DSA private key '\(keyName)' from keychain at", keychainURL.path, "\n", error)
            exit(1)
        }
    }
    else if args.count != 2 {
        printUsage()
        exit(1)
    }
    
    let archivesSourceDir = URL(fileURLWithPath: args.last!, isDirectory: true)
    let keys = loadPrivateKeys(privateDSAKey)

    do {
        let allUpdates = try makeAppcast(archivesSourceDir: archivesSourceDir, keys: keys, verbose:verbose);
        
        for (appcastFile, updates) in allUpdates {
            let appcastDestPath = URL(fileURLWithPath: appcastFile, relativeTo: archivesSourceDir);
            try writeAppcast(appcastDestPath:appcastDestPath, updates:updates);
            print("Written", appcastDestPath.path, "based on", updates.count, "updates");
        }
    } catch {
        print("Error generating appcast from directory", archivesSourceDir.path, "\n", error);
        exit(1);
    }
}

DispatchQueue.global().async(execute: {
    main();
    CFRunLoopStop(CFRunLoopGetMain());
});

CFRunLoopRun();
