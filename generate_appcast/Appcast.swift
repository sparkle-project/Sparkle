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

typealias UpdateVersion = String
typealias FeedName = String

struct Appcast {
    let inferredAppName: String
    let versionsInFeed: [UpdateVersion]
    let ignoredVersionsToInsert: Set<UpdateVersion>
    let archives: [UpdateVersion: ArchiveItem]
    let deltaPathsUsed: Set<String>
    let deltaFromVersionsUsed: Set<UpdateVersion>
}

func makeAppcasts(archivesSourceDir: URL, outputPathURL: URL?, cacheDirectory cacheDir: URL, keys: PrivateKeys, versions: Set<String>?, maxVersionsPerBranchInFeed: Int, newChannel: String?, majorVersion: String?, maximumDeltas: Int, deltaCompressionModeDescription: String, deltaCompressionLevel: UInt8, disableNestedCodeCheck: Bool, downloadURLPrefix: URL?, releaseNotesURLPrefix: URL?, verbose: Bool) throws -> [FeedName: Appcast] {
    let standardComparator = SUStandardVersionComparator()
    let descendingVersionComparator: (String, String) -> Bool = {
        return standardComparator.compareVersion($0, toVersion: $1) == .orderedDescending
    }
    
    let allUpdates = (try unarchiveUpdates(archivesSourceDir: archivesSourceDir, archivesDestDir: cacheDir, disableNestedCodeCheck: disableNestedCodeCheck, verbose: verbose))
        .sorted(by: { descendingVersionComparator($0.version, $1.version) })

    if allUpdates.count == 0 {
        throw makeError(code: .noUpdateError, "No usable archives found in \(archivesSourceDir.path)")
    }
    
    // Apply download and release notes prefixes
    for update in allUpdates {
        update.downloadUrlPrefix = downloadURLPrefix
        update.releaseNotesURLPrefix = releaseNotesURLPrefix
    }

    // Group updates by appcast feed
    var updatesByAppcast: [FeedName: [ArchiveItem]] = [:]
    for update in allUpdates {
        let appcastFile = update.feedURL?.lastPathComponent ?? "appcast.xml"
        updatesByAppcast[appcastFile, default: []].append(update)
    }
    
    // If a (single) output filename was specified on the command-line, but more than one
    // appcast file was found in the archives, then it's an error.
    if let outputPathURL = outputPathURL, updatesByAppcast.count > 1 {
        throw makeError(code: .appcastError, "Cannot write to \(outputPathURL.path): multiple appcasts found")
    }
    
    let group = DispatchGroup()
    var updateArchivesToSign: [ArchiveItem] = []
    
    var appcastByFeed: [FeedName: Appcast] = [:]
    for (feed, updates) in updatesByAppcast {
        var archivesTable: [UpdateVersion: ArchiveItem] = [:]
        for update in updates {
            archivesTable[update.version] = update
        }
        
        let feedURL = outputPathURL ?? archivesSourceDir.appendingPathComponent(feed)
        
        // Find all the update versions & branches from our existing feed (if available)
        let feedUpdateBranches: [UpdateVersion: UpdateBranch]
        if let reachable = try? feedURL.checkResourceIsReachable(), reachable {
            feedUpdateBranches = try readAppcast(archives: archivesTable, appcastURL: feedURL)
        } else {
            feedUpdateBranches = [:]
        }
        
        // Find which versions are new and old but aren't in the feed and that we should ignore/skip
        var ignoredVersionsToInsert: Set<UpdateVersion> = Set()
        var ignoredOldVersions: Set<UpdateVersion> = Set()
        if let versions = versions {
            // Note for this path we may be adding old updates to ignoredVersionsToInsert too.
            // It is difficult to differentiate between old and potential new updates that aren't in the feed
            // As a consequence, some old updates may not be pruned with this option.
            for update in updates {
                if feedUpdateBranches[update.version] == nil && !versions.contains(update.version) {
                    ignoredVersionsToInsert.insert(update.version)
                }
            }
        } else {
            // If the user doesn't specify which versions to generate updates for,
            // then by default we ignore generating updates that are less than the latest update in the existing feed
            // The reason why we need to do this is because new branch-specific flags the user can specify like the channel
            // or the major version will be applied to new unknown updates. We can only absolutely be sure to apply this to
            // updates that are greater in version than the top of the current feed, or if the user uses --versions.
            for latestUpdateCandidate in updates {
                if feedUpdateBranches[latestUpdateCandidate.version] != nil {
                    // Found the latest update in the feed
                    let latestUpdateVersionInFeed = latestUpdateCandidate.version
                    
                    // Filter out any new potential updates that are less than our latest update in our existing feed
                    for update in updates {
                        if feedUpdateBranches[update.version] == nil && descendingVersionComparator(latestUpdateVersionInFeed, update.version) {
                            ignoredOldVersions.insert(update.version)
                        }
                    }
                    break
                }
            }
        }
        
        // Find new update versions and their branches
        var newUpdateBranches: [UpdateVersion: UpdateBranch] = [:]
        do {
            for update in updates {
                if !ignoredOldVersions.contains(update.version) && !ignoredVersionsToInsert.contains(update.version) && feedUpdateBranches[update.version] == nil {
                    newUpdateBranches[update.version] = UpdateBranch(minimumSystemVersion: update.minimumSystemVersion, maximumSystemVersion: nil, minimumAutoupdateVersion: majorVersion, channel: newChannel)
                }
            }
        }
        
        // Compute latest versions per distinct branch we need to keep
        // Also compute the batch of recent versions we should preserve/add in the feed
        let versionsPreservedInFeed: [UpdateVersion]
        var latestVersionPerBranch: Set<UpdateVersion> = []
        do {
            // Group update versions by branch
            var updatesGroupedByBranch: [UpdateBranch: [UpdateVersion]] = [:]

            for (version, branch) in feedUpdateBranches {
                updatesGroupedByBranch[branch, default: []].append(version)
            }
            for (version, branch) in newUpdateBranches {
                updatesGroupedByBranch[branch, default: []].append(version)
            }
            
            // Grab latest batch of versions per branch
            for (branch, versions) in updatesGroupedByBranch {
                updatesGroupedByBranch[branch] = Array(versions.sorted(by: descendingVersionComparator).prefix(maxVersionsPerBranchInFeed))
            }
            
            // Remove extraneous versions for branches that have converged,
            // as long as the user doesn't opt into keeping all versions in the feed
            if maxVersionsPerBranchInFeed < Int.max {
                for (branch, versions) in updatesGroupedByBranch {
                    guard branch.channel != nil else {
                        continue
                    }
                    
                    let defaultChannelBranch = UpdateBranch(minimumSystemVersion: branch.minimumSystemVersion, maximumSystemVersion: branch.maximumSystemVersion, minimumAutoupdateVersion: branch.minimumAutoupdateVersion, channel: nil)
                    
                    guard let defaultChannelVersions = updatesGroupedByBranch[defaultChannelBranch] else {
                        continue
                    }
                    
                    if descendingVersionComparator(defaultChannelVersions[0], versions[0]) {
                        updatesGroupedByBranch[branch] = [versions[0]]
                    }
                }
            }
            
            // Grab latest versions per branch
            var latestBatchOfVersionsPerBranch: Set<UpdateVersion> = []
            for (_, versions) in updatesGroupedByBranch {
                latestBatchOfVersionsPerBranch.formUnion(versions)
                latestVersionPerBranch.insert(versions[0])
            }
            
            versionsPreservedInFeed = Array(latestBatchOfVersionsPerBranch).sorted(by: descendingVersionComparator)
        }

        // Update signatures for the latest updates we keep in the feed
        for version in versionsPreservedInFeed {
            guard let update = archivesTable[version] else {
                continue
            }
            
            updateArchivesToSign.append(update)
            
            group.enter()
            DispatchQueue.global().async {
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
                if let privateDSAKey = keys.privateDSAKey {
                    do {
                        update.dsaSignature = try dsaSignature(path: update.archivePath, privateDSAKey: privateDSAKey)
                    } catch {
                        print(update, error)
                    }
                } else if update.supportsDSA {
                    print("Note: did not sign with legacy DSA \(update.archivePath.path) because private DSA key file was not specified")
                }
#endif
                if let publicEdKey = update.publicEdKey {
                    if let privateEdKey = keys.privateEdKey, let expectedPublicKey = keys.publicEdKey {
                        if publicEdKey == expectedPublicKey {
                            do {
                                update.edSignature = try edSignature(path: update.archivePath, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
                            } catch {
                                update.signingError = error
                                print(update, error)
                            }
                        } else {
                            print("Warning: SUPublicEDKey in the app \(update.archivePath.path) does not match key EdDSA in the Keychain. Run generate_keys and update Info.plist to match")
                        }
                    } else {
                        let error = makeError(code: .insufficientSigningError, "Could not sign \(update.archivePath.path) due to lack of private EdDSA key")
                        
                        update.signingError = error
                        print("Error: could not sign \(update.archivePath.path) due to lack of private EdDSA key")
                    }
                }

                group.leave()
            }
        }
        
        // Generate delta updates from the latest updates we keep
        // Keep track of which delta archives we need referenced in the appcast still
        var deltaPathsUsed: Set<String> = []
        var deltaFromVersionsUsed: Set<UpdateVersion> = []
        for version in versionsPreservedInFeed {
            guard let latestItem = archivesTable[version] else {
                continue
            }
            
            // We only generate deltas for the latest version per branch,
            // but we still wanted to record the used delta updates for a batch of recent updates
            // This is to support rollback in case the top newly generated update isn't exactly what the user wants
            let generatingDeltas = latestVersionPerBranch.contains(version)
            var numDeltas = 0
            let appBaseName = latestItem.appPath.deletingPathExtension().lastPathComponent
            for item in updates {
                if numDeltas >= maximumDeltas {
                    break
                }

                // No downgrades
                if .orderedAscending != standardComparator.compareVersion(item.version, toVersion: latestItem.version) {
                    continue
                }
                
                // Old version will not be able to verify the new version
                if !item.supportsDSA && item.publicEdKey == nil {
                    continue
                }

                let deltaBaseName = appBaseName + latestItem.version + "-" + item.version
                let deltaPath = archivesSourceDir.appendingPathComponent(deltaBaseName).appendingPathExtension("delta")
                
                deltaPathsUsed.insert(deltaPath.path)
                deltaFromVersionsUsed.insert(item.version)
                
                numDeltas += 1
                
                if !generatingDeltas {
                    continue
                }

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
                            try SUCodeSigningVerifier.codeSignatureIsValid(atBundleURL: latestItem.appPath, andMatchesSignatureAtBundleURL: item.appPath)
                        } catch {
                            print("Warning: found mismatch code signing identity between \(item) and \(latestItem)")
                        }
                    }
                        
                    do {
                        // Decide the most appropriate delta version
                        let deltaVersion: SUBinaryDeltaMajorVersion
                        if let frameworkVersion = item.frameworkVersion {
                            switch standardComparator.compareVersion(frameworkVersion, toVersion: "2041") {
                            case .orderedSame:
                                fallthrough
                            case .orderedDescending:
                                deltaVersion = .version4
                            case .orderedAscending:
                                switch standardComparator.compareVersion(frameworkVersion, toVersion: "2010") {
                                case .orderedSame:
                                    fallthrough
                                case .orderedDescending:
                                    deltaVersion = .version3
                                case .orderedAscending:
                                    deltaVersion = .version2
                                }
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
                    delta = DeltaUpdate(fromVersion: item.version, archivePath: deltaPath, sparkleExecutableFileSize: item.sparkleExecutableFileSize, sparkleLocales: item.sparkleLocales)
                }

                // Require delta to be a bit smaller
                if delta.fileSize / 7 > latestItem.fileSize / 8 {
                    markDeltaAsIgnored(delta: delta, markerPath: ignoreMarkerPath)
                    continue
                }

                group.enter()
                DispatchQueue.global().async {
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
                    if item.supportsDSA, let privateDSAKey = keys.privateDSAKey {
                        do {
                            delta.dsaSignature = try dsaSignature(path: deltaPath, privateDSAKey: privateDSAKey)
                        } catch {
                            print(delta.archivePath.lastPathComponent, error)
                        }
                    }
#endif
                    if let publicEdKey = item.publicEdKey, let privateEdKey = keys.privateEdKey {
                        do {
                            delta.edSignature = try edSignature(path: deltaPath, publicEdKey: publicEdKey, privateEdKey: privateEdKey)
                        } catch {
                            print(delta.archivePath.lastPathComponent, error)
                        }
                    }
                    do {
                        var hasAnyDSASignature = (delta.edSignature != nil)
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
                        hasAnyDSASignature = hasAnyDSASignature || (delta.dsaSignature != nil)
#endif
                        if hasAnyDSASignature {
                            latestItem.deltas.append(delta)
                        } else {
                            markDeltaAsIgnored(delta: delta, markerPath: ignoreMarkerPath)
                            print("Delta \(delta.archivePath.path) ignored, because it could not be signed")
                        }
                    }
                    group.leave()
                }
            }
        }
        
        let inferredAppName = updates[0].appPath.deletingPathExtension().lastPathComponent
        let appcast = Appcast(inferredAppName: inferredAppName, versionsInFeed: versionsPreservedInFeed, ignoredVersionsToInsert: ignoredVersionsToInsert, archives: archivesTable, deltaPathsUsed: deltaPathsUsed, deltaFromVersionsUsed: deltaFromVersionsUsed)
        appcastByFeed[feed] = appcast
    }
    
    group.wait()
    
    // Check for fatal signing errors
    for update in updateArchivesToSign {
        if let signingError = update.signingError {
            throw signingError
        }
    }

    return appcastByFeed
}

func moveOldUpdatesFromAppcasts(archivesSourceDir: URL, oldFilesDirectory: URL, cacheDirectory: URL, appcasts: [Appcast], autoPruneUpdates: Bool) -> (movedCount: Int, prunedCount: Int) {
    let fileManager = FileManager.default
    let suFileManager = SUFileManager()
    
    // Create old files updates directory if needed
    var createdOldFilesDirectory = false
    let makeOldFilesDirectory: () -> Bool = {
        guard !createdOldFilesDirectory else {
            return true
        }
        
        if fileManager.fileExists(atPath: oldFilesDirectory.path) {
            createdOldFilesDirectory = true
            return true
        }
        
        do {
            try fileManager.createDirectory(at: oldFilesDirectory, withIntermediateDirectories: false)
            
            createdOldFilesDirectory = true
            
            return true
        } catch {
            print("Warning: failed to create \(oldFilesDirectory.lastPathComponent) in \(archivesSourceDir.lastPathComponent): \(error)")
            return false
        }
    }
    
    var movedItemsCount = 0
    
    // Move aside all old unused update items
    for appcast in appcasts {
        let versionsInFeedSet = Set(appcast.versionsInFeed)
        for (version, update) in appcast.archives {
            guard !versionsInFeedSet.contains(version) && !appcast.deltaFromVersionsUsed.contains(version) && !appcast.ignoredVersionsToInsert.contains(version) else {
                continue
            }
            
            let archivePath = update.archivePath
            
            guard makeOldFilesDirectory() else {
                return (movedItemsCount, 0)
            }
            
            do {
                try suFileManager.updateModificationAndAccessTimeOfItem(at: archivePath)
            } catch {
                print("Warning: failed to update modification time for \(archivePath.path): \(error)")
            }
            
            do {
                try fileManager.moveItem(at: archivePath, to: oldFilesDirectory.appendingPathComponent(archivePath.lastPathComponent))
                
                movedItemsCount += 1
                
                // Remove cache for the update
                let appCachePath = update.appPath.deletingLastPathComponent()
                let _ = try? fileManager.removeItem(at: appCachePath)
            } catch {
                print("Warning: failed to move \(archivePath.lastPathComponent) to \(oldFilesDirectory.lastPathComponent): \(error)")
            }
            
            let htmlReleaseNotesFile = archivePath.deletingPathExtension().appendingPathExtension("html")
            let plainTextReleaseNotesFile = archivePath.deletingPathExtension().appendingPathExtension("txt")
            
            let releaseNotesFile: URL?
            if fileManager.fileExists(atPath: htmlReleaseNotesFile.path) {
                releaseNotesFile = htmlReleaseNotesFile
            } else if fileManager.fileExists(atPath: plainTextReleaseNotesFile.path) {
                releaseNotesFile = plainTextReleaseNotesFile
            } else {
                releaseNotesFile = nil
            }
            
            if let releaseNotesFile = releaseNotesFile {
                do {
                    try suFileManager.updateModificationAndAccessTimeOfItem(at: releaseNotesFile)
                } catch {
                    print("Warning: failed to update modification time for \(releaseNotesFile.path): \(error)")
                }
                
                do {
                    try fileManager.moveItem(at: releaseNotesFile, to: oldFilesDirectory.appendingPathComponent(releaseNotesFile.lastPathComponent))
                    
                    movedItemsCount += 1
                } catch {
                    print("Warning: failed to move \(releaseNotesFile.lastPathComponent) to \(oldFilesDirectory.lastPathComponent): \(error)")
                }
            }
        }
    }
    
    // Move aside all unused delta items in the archives directory
    // We will be missing out on ignore markers in the cache for delta items because they're difficult to fetch
    // However they are zero-sized so they don't take much space anyway
    do {
        let directoryContents = try fileManager.contentsOfDirectory(atPath: archivesSourceDir.path)
        for filename in directoryContents {
            guard filename.hasSuffix(".delta") else {
                continue
            }
            
            let deltaURL = archivesSourceDir.appendingPathComponent(filename)
            do {
                var foundDeltaItemUsage = false
                for appcast in appcasts {
                    if appcast.deltaPathsUsed.contains(deltaURL.path) {
                        foundDeltaItemUsage = true
                        break
                    }
                }
                
                guard !foundDeltaItemUsage else {
                    continue
                }
            }
            
            guard makeOldFilesDirectory() else {
                return (movedItemsCount, 0)
            }
            
            movedItemsCount += 1
            
            do {
                try suFileManager.updateModificationAndAccessTimeOfItem(at: deltaURL)
            } catch {
                print("Warning: Failed to update modification time for \(deltaURL.lastPathComponent): \(error)")
            }
            
            do {
                try fileManager.moveItem(at: deltaURL, to: oldFilesDirectory.appendingPathComponent(filename))
            } catch {
                print("Warning: failed to move \(deltaURL.lastPathComponent) to \(oldFilesDirectory.lastPathComponent): \(error)")
            }
        }
    } catch {
        print("Warning: failed to list contents of \(archivesSourceDir.lastPathComponent) during pruning: \(error)")
    }
    
    var pruneCount = 0
    if autoPruneUpdates {
        // Garbage collect the old updates directory
        do {
            let directoryContents = try fileManager.contentsOfDirectory(atPath: oldFilesDirectory.path)
            
            // Delete files that have roughly not been touched for 14 days
            let prunedFileDeletionInterval: TimeInterval = 86400 * 14
            
            let currentDate = Date()
            for filename in directoryContents {
                guard !filename.hasPrefix(".") else {
                    continue
                }
                
                let fileURL = oldFilesDirectory.appendingPathComponent(filename)
                
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let lastModificationDate = resourceValues.contentModificationDate {
                    if currentDate.timeIntervalSince(lastModificationDate) >= prunedFileDeletionInterval {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            pruneCount += 1
                        } catch {
                            print("Warning: failed to delete old update file \(oldFilesDirectory.lastPathComponent)/\(fileURL.lastPathComponent): \(error)")
                        }
                    }
                }
            }
        } catch {
            // Nothing to log for failing to fetch prunedDirectory
        }
    }
    
    return (movedItemsCount, pruneCount)
}

func markDeltaAsIgnored(delta: DeltaUpdate, markerPath: URL) {
    _ = try? FileManager.default.removeItem(at: delta.archivePath)
    _ = try? Data.init().write(to: markerPath); // 0-sized file
}
