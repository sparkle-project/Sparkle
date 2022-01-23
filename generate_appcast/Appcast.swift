//
//  Created by Kornel on 23/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

func makeError(code: SUError, _ description: String) -> NSError {
    return NSError(domain: SUSparkleErrorDomain, code: Int(OSStatus(code.rawValue)), userInfo: [
        NSLocalizedDescriptionKey: description,
        ])
}

func makeAppcast(archivesSourceDir: URL, cacheDirectory cacheDir: URL, keys: PrivateKeys, versions: Set<String>?, maximumDeltas: Int, deltaCompressionModeDescription: String, deltaCompressionLevel: UInt8, disableNestedCodeCheck: Bool, verbose: Bool) throws -> [String: [ArchiveItem]] {
    let comparator = SUStandardVersionComparator()

    let allUpdates = (try unarchiveUpdates(archivesSourceDir: archivesSourceDir, archivesDestDir: cacheDir, disableNestedCodeCheck: disableNestedCodeCheck, verbose: verbose))
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
            // If the new versions are specified, ignore everything else
            if let versions = versions, !versions.contains(update.version) {
                continue
            }
            
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
                if numDeltas >= maximumDeltas {
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
                    // Test if old and new app have the same code signing signature. If not, omit a warning.
                    // This is a good time to do this check because our delta handling code sets a marker
                    // to avoid this path each time generate_appcast is called.
                    let oldAppCodeSigned = SUCodeSigningVerifier.bundle(atURLIsCodeSigned: item.appPath)
                    let newAppCodeSigned = SUCodeSigningVerifier.bundle(atURLIsCodeSigned: latestItem.appPath)
                    
                    if oldAppCodeSigned != newAppCodeSigned && !newAppCodeSigned {
                        print("Warning: New app is not code signed but older version (\(item)) is: \(latestItem)")
                    } else if oldAppCodeSigned && newAppCodeSigned {
                        do {
                            try SUCodeSigningVerifier.codeSignature(atBundleURL: item.appPath, matchesSignatureAtBundleURL: latestItem.appPath)
                        } catch {
                            print("Warning: found mismatch code signing identity between \(item) and \(latestItem)")
                        }
                    }
                        
                    do {
                        // Decide the most appropriate delta version
                        let deltaVersion: SUBinaryDeltaMajorVersion
                        if let frameworkVersion = item.frameworkVersion {
                            switch comparator.compareVersion(frameworkVersion, toVersion: "2010") {
                            case .orderedSame:
                                fallthrough
                            case .orderedDescending:
                                deltaVersion = .version3
                            case .orderedAscending:
                                deltaVersion = .version2
                            }
                        } else {
                            deltaVersion = SUBinaryDeltaMajorVersionDefault
                            print("Warning: Sparkle.framework version for \(item.appPath.lastPathComponent) (\(item.shortVersion) (\(item.version))) was not found. Falling back to generating delta using default delta version..")
                        }
                        
                        let requestedDeltaCompressionMode = deltaCompressionModeFromDescription(deltaCompressionModeDescription, nil)
                        
                        // Version 2 formats only support bzip2, none, and default options
                        let deltaCompressionMode: SPUDeltaCompressionMode
                        if deltaVersion == .version2 {
                            switch requestedDeltaCompressionMode {
                            case .LZFSE:
                                fallthrough
                            case .LZ4:
                                fallthrough
                            case .LZMA:
                                fallthrough
                            case .ZLIB:
                                deltaCompressionMode = .bzip2
                                print("Warning: Delta compression mode '\(deltaCompressionModeDescription)' was requested but using default compression instead because version 2 delta file from version \(item.version) needs to be generated..")
                            case SPUDeltaCompressionModeDefault:
                                fallthrough
                            case .none:
                                fallthrough
                            case .bzip2:
                                deltaCompressionMode = requestedDeltaCompressionMode
                            @unknown default:
                                // This shouldn't happen
                                print("Warning: failed to parse delta compression mode \(deltaCompressionModeDescription). There is a logic bug in generate_appcast.")
                                deltaCompressionMode = SPUDeltaCompressionModeDefault
                            }
                        } else {
                            deltaCompressionMode = requestedDeltaCompressionMode
                        }
                        
                        delta = try DeltaUpdate.create(from: item, to: latestItem, deltaVersion: deltaVersion, deltaCompressionMode: deltaCompressionMode, deltaCompressionLevel: deltaCompressionLevel, archivePath: deltaPath)
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
