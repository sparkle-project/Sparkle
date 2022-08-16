//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

func unarchive(itemPath: URL, archiveDestDir: URL, callback: @escaping (Error?) -> Void) {
    let fileManager = FileManager.default
    let tempDir = archiveDestDir.appendingPathExtension("tmp")
    let itemCopy = tempDir.appendingPathComponent(itemPath.lastPathComponent)

    _ = try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [:])

    do {
        do {
            try fileManager.linkItem(at: itemPath, to: itemCopy)
        } catch {
            try fileManager.copyItem(at: itemPath, to: itemCopy)
        }
        if let unarchiver = SUUnarchiver.unarchiver(forPath: itemCopy.path, updatingHostBundlePath: nil, decryptionPassword: nil, expectingInstallationType: SPUInstallationTypeApplication) {
            unarchiver.unarchive(completionBlock: { (error: Error?) in
                if error != nil {
                    callback(error)
                    return
                }

                _ = try? fileManager.removeItem(at: itemCopy)
                do {
                    try fileManager.moveItem(at: tempDir, to: archiveDestDir)
                    callback(nil)
                } catch {
                    callback(error)
                }
            }, progressBlock: nil)
        } else {
            _ = try? fileManager.removeItem(at: itemCopy)
            callback(makeError(code: .unarchivingError, "Not a supported archive format: \(itemCopy)"))
        }
    } catch {
        _ = try? fileManager.removeItem(at: tempDir)
        callback(error)
    }
}

func unarchiveUpdates(archivesSourceDir: URL, archivesDestDir: URL, disableNestedCodeCheck: Bool, verbose: Bool) throws -> [ArchiveItem] {
    if verbose {
        print("Unarchiving to temp directory", archivesDestDir.path)
    }

    let group = DispatchGroup()

    let fileManager = FileManager.default

    var unarchived: [ArchiveItem] = []

    let dir = try fileManager.contentsOfDirectory(atPath: archivesSourceDir.path)
    var running = 0
    for item in dir.filter({ !$0.hasPrefix(".") && !$0.hasSuffix(".delta") && !$0.hasSuffix(".xml") && !$0.hasSuffix(".html") }) {
        let itemPath = archivesSourceDir.appendingPathComponent(item)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: itemPath.path, isDirectory: &isDir) && isDir.boolValue {
            continue
        }
        
        let archiveDestDir: URL
        if let hash = itemPath.sha256String() {
            archiveDestDir = archivesDestDir.appendingPathComponent(hash)
        } else {
            archiveDestDir = archivesDestDir.appendingPathComponent(itemPath.lastPathComponent)
        }

        let addItem = { (validateBundle: Bool) in
            do {
                let item = try ArchiveItem(fromArchive: itemPath, unarchivedDir: archiveDestDir, validateBundle: validateBundle, disableNestedCodeCheck: disableNestedCodeCheck)
                if verbose {
                    print("Found archive", item)
                }
                objc_sync_enter(unarchived)
                unarchived.append(item)
                objc_sync_exit(unarchived)
            } catch {
                print("Skipped", item, error)
            }
        }

        if fileManager.fileExists(atPath: archiveDestDir.path) {
            addItem(false)
        } else {
            group.enter()
            unarchive(itemPath: itemPath, archiveDestDir: archiveDestDir) { (error: Error?) in
                if let error = error {
                    print("Could not unarchive", itemPath.path, error)
                } else {
                    addItem(true)
                }
                group.leave()
            }
        }

        // Crude limit of concurrency
        running += 1
        if running >= 8 {
            running = 0
            group.wait()
        }
    }

    group.wait()

    return unarchived
}
