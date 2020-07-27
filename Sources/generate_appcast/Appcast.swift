//
//  Created by Kornel on 23/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

// Maximum number of delta updates (per OS).
let maxDeltas = 5

func makeError(code: SUError, _ description: String) -> NSError {
    return NSError(domain: SUSparkleErrorDomain, code: Int(OSStatus(code.rawValue)), userInfo: [
        NSLocalizedDescriptionKey: description,
        ])
}

func makeAppcast(archivesSourceDir: URL, keys: PrivateKeys, verbose: Bool) throws -> [String: [ArchiveItem]] {
    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Sparkle_generate_appcast")
    let comparator = SUStandardVersionComparator()

    let allUpdates = (try unarchiveUpdates(archivesSourceDir: archivesSourceDir, archivesDestDir: cacheDir, verbose: verbose))
        .sorted(by: {
            .orderedDescending == comparator.compareVersion($0.version, toVersion: $1.version)
        })

    if allUpdates.count == 0 {
        throw makeError(code: .noUpdateError, "No usable archives found in \(archivesSourceDir.path)")
    }

    var updatesByAppcast: [String: [ArchiveItem]] = [:]

    let group = DispatchGroup()

    for update in allUpdates {
        group.enter()
        DispatchQueue.global().async {
            if let privateDSAKey = keys.privateDSAKey {
                do {
                    update.dsaSignature = try dsaSignature(path: update.archivePath, privateDSAKey: privateDSAKey)
                } catch {
                    print(update, error)
                }
            } else if update.supportsDSA {
                print("Note: did not sign with legacy DSA \(update.archivePath.path) because private DSA key file was not specified")
            }
            if let publicEdKey = update.publicEdKey {
                if let privateEdKey = keys.privateEdKey, let expectedPublicKey = keys.publicEdKey {
                    if publicEdKey == expectedPublicKey {
                        do {
                            update.edSignature = try edSignature(path: update.archivePath, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
                        } catch {
                            print(update, error)
                        }
                    } else {
                        print("Warning: SUPublicEDKey in the app \(update.archivePath.path) does not match key EdDSA in the Keychain. Run generate_keys and update Info.plist to match")
                    }
                } else {
                    print("Warning: could not sign \(update.archivePath.path) due to lack of private EdDSA key")
                }
            }

            group.leave()
        }

        let appcastFile = update.feedURL?.lastPathComponent ?? "appcast.xml"
        if updatesByAppcast[appcastFile] == nil {
            updatesByAppcast[appcastFile] = []
        }
        updatesByAppcast[appcastFile]!.append(update)
    }

    for (_, updates) in updatesByAppcast {
        var latestUpdatePerOS: [String: ArchiveItem] = [:]

        for update in updates {
            // items are ordered starting latest first
            let os = update.minimumSystemVersion
            if latestUpdatePerOS[os] == nil {
                latestUpdatePerOS[os] = update
            }
        }

        for (_, latestItem) in latestUpdatePerOS {
            var numDeltas = 0
            let appBaseName = latestItem.appPath.deletingPathExtension().lastPathComponent
            for item in updates {
                if numDeltas > maxDeltas {
                    break
                }

                // No downgrades
                if .orderedAscending != comparator.compareVersion(item.version, toVersion: latestItem.version) {
                    continue
                }
                // Old version will not be able to verify the new version
                if !item.supportsDSA && item.publicEdKey == nil {
                    continue
                }

                let deltaBaseName = appBaseName + latestItem.version + "-" + item.version
                let deltaPath = archivesSourceDir.appendingPathComponent(deltaBaseName).appendingPathExtension("delta")

                var delta: DeltaUpdate
                let ignoreMarkerPath = cacheDir.appendingPathComponent(deltaPath.lastPathComponent).appendingPathExtension(".ignore")
                let fm = FileManager.default
                if fm.fileExists(atPath: ignoreMarkerPath.path) {
                    continue
                }
                if !fm.fileExists(atPath: deltaPath.path) {
                    do {
                        delta = try DeltaUpdate.create(from: item, to: latestItem, archivePath: deltaPath)
                    } catch {
                        print("Could not create delta update", deltaPath.path, error)
                        continue
                    }
                } else {
                    delta = DeltaUpdate(fromVersion: item.version, archivePath: deltaPath)
                }

                numDeltas += 1

                // Require delta to be a bit smaller
                if delta.fileSize / 7 > latestItem.fileSize / 8 {
                    markDeltaAsIgnored(delta: delta, markerPath: ignoreMarkerPath)
                    continue
                }

                group.enter()
                DispatchQueue.global().async {
                    if item.supportsDSA, let privateDSAKey = keys.privateDSAKey {
                        do {
                            delta.dsaSignature = try dsaSignature(path: deltaPath, privateDSAKey: privateDSAKey)
                        } catch {
                            print(delta.archivePath.lastPathComponent, error)
                        }
                    }
                    if let publicEdKey = item.publicEdKey, let privateEdKey = keys.privateEdKey {
                        do {
                            delta.edSignature = try edSignature(path: deltaPath, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
                        } catch {
                            print(delta.archivePath.lastPathComponent, error)
                        }
                    }
                    if delta.dsaSignature != nil || delta.edSignature != nil {
                        latestItem.deltas.append(delta)
                    } else {
                        markDeltaAsIgnored(delta: delta, markerPath: ignoreMarkerPath)
                        print("Delta \(delta.archivePath.path) ignored, because it could not be signed")
                    }
                    group.leave()
                }
            }
        }
    }

    group.wait()

    return updatesByAppcast
}

func markDeltaAsIgnored(delta: DeltaUpdate, markerPath: URL) {
    _ = try? FileManager.default.removeItem(at: delta.archivePath)
    _ = try? Data.init().write(to: markerPath); // 0-sized file
}
