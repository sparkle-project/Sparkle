//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

func unarchive(itemPath: URL, archiveDestDir: URL, callback: @escaping (Error?) -> Void) {
    let fileManager = FileManager.default
    let tempDir = archiveDestDir.appendingPathExtension("tmp")

    _ = try? fileManager.removeItem(at: tempDir)
    _ = try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [:])

    if let unarchiver = SUUnarchiver.unarchiver(forPath: itemPath.path, extractionDirectory: tempDir.path, updatingHostBundlePath: nil, decryptionPassword: nil, expectingInstallationType: SPUInstallationTypeApplication) {
        unarchiver.unarchive(completionBlock: { (error: Error?) in
            if error != nil {
                callback(error)
                return
            }

            do {
                try fileManager.moveItem(at: tempDir, to: archiveDestDir)
                callback(nil)
            } catch {
                callback(error)
            }
        }, progressBlock: nil, waitForCleanup: true)
    } else {
        callback(makeError(code: .unarchivingError, "Not a supported archive format: \(itemPath.path)"))
    }
}

func unarchiveUpdates(archivesSourceDir: URL, archivesDestDir: URL, disableNestedCodeCheck: Bool, verbose: Bool) throws -> [ArchiveItem] {
    if verbose {
        print("Unarchiving to temp directory", archivesDestDir.path)
    }

    let group = DispatchGroup()

    let fileManager = FileManager.default

    // Create a dictionary of archive destination directories -> archive source path
    // so we can ignore duplicate archive entries before trying to unarchive archives in parallel
    var fileEntries: [URL: URL] = [:]
    let dir = try fileManager.contentsOfDirectory(atPath: archivesSourceDir.path)
    for item in dir {
        if item.hasPrefix(".") {
            continue
        }
        
        let itemURL = archivesSourceDir.appendingPathComponent(item)
        let fileExtension = itemURL.pathExtension
        // Note: keep this list in sync with SUPipedUnarchiver
        guard ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "lzma", "dmg", "aar", "yaa"].contains(fileExtension) else {
            continue
        }
        
        let itemPath = archivesSourceDir.appendingPathComponent(item)
        
        // Ignore directories
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
        
        // Ignore duplicate archives
        if let existingItemPath = fileEntries[archiveDestDir] {
            throw makeError(code: .appcastError, "Duplicate update archives are not supported. Found '\(existingItemPath.lastPathComponent)' and '\(itemPath.lastPathComponent)'. Please remove one of them from the appcast generation directory.")
        }
        
        fileEntries[archiveDestDir] = itemPath
    }
    
    var unarchived: [String: ArchiveItem] = [:]
    var updateParseError: Error? = nil
    
    var running = 0
    for (archiveDestDir, itemPath) in fileEntries {
        let addItem = { (validateBundle: Bool) in
            do {
                let item = try ArchiveItem(fromArchive: itemPath, unarchivedDir: archiveDestDir, validateBundle: validateBundle, disableNestedCodeCheck: disableNestedCodeCheck)
                if verbose {
                    print("Found archive", item)
                }
                objc_sync_enter(unarchived)
                // Make sure different archives don't contain the same update too
                if let existingArchive = unarchived[item.version] {
                    updateParseError = makeError(code: .appcastError, "Duplicate updates are not supported. Found archives '\(existingArchive.archivePath.lastPathComponent)' and '\(itemPath.lastPathComponent)' which contain the same bundle version. Please remove one of these archives from the appcast generation directory.")
                } else {
                    unarchived[item.version] = item
                }
                objc_sync_exit(unarchived)
            } catch {
                print("Skipped", itemPath.lastPathComponent, error)
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
    
    if let updateParseError = updateParseError {
        throw updateParseError
    }

    return Array(unarchived.values)
}
