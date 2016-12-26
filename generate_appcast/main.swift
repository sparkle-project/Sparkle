//
//  main.swift
//  Appcast
//
//  Created by Kornel on 20/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

func main() {
    let args = CommandLine.arguments;
    if args.count < 3 {
        let command = URL(fileURLWithPath: args[0]).lastPathComponent;
        print("Generate appcast from a directory of Sparkle updates\nUsage: \(command) <private key path> <directory with update archives>\n",
            " e.g. \(command) dsa_priv.pem archives/\n",
            " Appcast files and deltas will be written to the archives directory.\n",
            " Note that pkg-based updates are not supported.\n"
        )
        exit(1);
    }

    let privateKeyPath = URL(fileURLWithPath: args[1]);
    let archivesSourceDir = URL(fileURLWithPath: args[2], isDirectory:true);

    do {
        let privateKey = try loadPrivateKey(privateKeyPath: privateKeyPath);
        do {
            let allUpdates = try makeAppcast(archivesSourceDir: archivesSourceDir, privateKey: privateKey);

            for (appcastFile, updates) in allUpdates {
                let appcastDestPath = URL(fileURLWithPath: appcastFile, relativeTo: archivesSourceDir);
                try writeAppcast(appcastDestPath:appcastDestPath, updates:updates);
                print("Written", appcastDestPath.path, "based on", updates.count, "updates");
            }
        } catch {
            print("Error generating appcast from directory", archivesSourceDir.path, "\n", error);
            exit(1);
        }
    } catch {
        print("Unable to load DSA private key from", privateKeyPath.path, "\n", error);
        exit(1);
    }
}

DispatchQueue.global().async(execute: {
    main();
    CFRunLoopStop(CFRunLoopGetMain());
});

CFRunLoopRun();
