//
//  Created by Kornel on 23/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

// Maximum number of delta updates (per OS).
let maxDeltas = 5;

func makeError(code: SUError, _ description: String) -> NSError {
    return NSError(domain: SUSparkleErrorDomain, code: Int(OSStatus(code.rawValue)), userInfo: [
        NSLocalizedDescriptionKey: description,
        ]);
}

func makeAppcast(archivesSourceDir: URL, privateKey: SecKey) throws -> [String:[ArchiveItem]] {
    let comparator = SUStandardVersionComparator();

    let allUpdates = (try unarchiveUpdates(archivesSourceDir: archivesSourceDir))
        .sorted(by: {
            .orderedDescending == comparator.compareVersion($0.version, toVersion:$1.version)
        })

    if allUpdates.count == 0 {
        throw makeError(code: .noUpdateError, "No usable archives found in \(archivesSourceDir.path)");
    }

    var updatesByAppcast:[String:[ArchiveItem]] = [:];

    let group = DispatchGroup();

    for update in allUpdates {
        group.enter();
        DispatchQueue.global().async {
            do {
                update.dsaSignature = try dsaSignature(path: update.archivePath, privateKey: privateKey);
            } catch {
                print(update, error);
            }
            group.leave();
        }

        let appcastFile = update.feedURL?.lastPathComponent ?? "appcast.xml";
        if updatesByAppcast[appcastFile] == nil {
            updatesByAppcast[appcastFile] = [];
        }
        updatesByAppcast[appcastFile]!.append(update);
    }

    for (_, updates) in updatesByAppcast {
        var latestUpdatePerOS:[String:ArchiveItem] = [:];

        for update in updates {
            // items are ordered starting latest first
            let os = update.minimumSystemVersion;
            if latestUpdatePerOS[os] == nil {
                latestUpdatePerOS[os] = update;
            }
        }

        for (_,latestItem) in latestUpdatePerOS {
            var numDeltas = 0;
            let appBaseName = latestItem.appPath.deletingPathExtension().lastPathComponent;
            for item in updates {
                // No downgrades
                if .orderedAscending != comparator.compareVersion(item.version, toVersion: latestItem.version) {
                    continue;
                }

                let deltaBaseName = appBaseName + latestItem.version + "-" + item.version;
                let deltaPath = archivesSourceDir.appendingPathComponent(deltaBaseName).appendingPathExtension("delta");

                var delta:DeltaUpdate;
                if !FileManager.default.fileExists(atPath: deltaPath.path) {
                    do {
                        delta = try DeltaUpdate.create(from: item, to: latestItem, archivePath: deltaPath);
                    } catch {
                        print("Could not create delta update", deltaPath.path, error);
                        continue;
                    }
                } else {
                    delta = DeltaUpdate(fromVersion: item.version, archivePath: deltaPath);
                }

                // Require delta to be a bit smaller
                if delta.fileSize / 7 < latestItem.fileSize / 8 {
                    // Max 3 deltas per version (arbitrary limit to reduce amount of work)
                    numDeltas += 1;
                    if numDeltas > maxDeltas {
                        break;
                    }

                    group.enter();
                    DispatchQueue.global().async {
                        do {
                            delta.dsaSignature = try dsaSignature(path: deltaPath, privateKey: privateKey);
                            latestItem.deltas.append(delta);
                        } catch {
                            print(delta.archivePath.lastPathComponent, error);
                        }
                        group.leave();
                    }
                }
            }
        }
    }

    group.wait();

    return updatesByAppcast;
}
