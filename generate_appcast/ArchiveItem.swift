//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

class DeltaUpdate {
    let fromVersion: String
    let archivePath: URL
    var dsaSignature: String?
    var edSignature: String?

    init(fromVersion: String, archivePath: URL) {
        self.archivePath = archivePath
        self.fromVersion = fromVersion
    }

    var fileSize: Int64 {
        let archiveFileAttributes = try! FileManager.default.attributesOfItem(atPath: self.archivePath.path)
        return (archiveFileAttributes[.size] as! NSNumber).int64Value
    }

    class func create(from: ArchiveItem, to: ArchiveItem, archivePath: URL) throws -> DeltaUpdate {
        var applyDiffError: NSError?

        if !createBinaryDelta(from.appPath.path, to.appPath.path, archivePath.path, .beigeMajorVersion, false, &applyDiffError) {
            throw applyDiffError!
        }

        return DeltaUpdate(fromVersion: from.version, archivePath: archivePath)
    }
}

class ArchiveItem: CustomStringConvertible {
    let version: String
    // swiftlint:disable identifier_name
    let _shortVersion: String?
    let minimumSystemVersion: String
    let archivePath: URL
    let appPath: URL
    let feedURL: URL?
    let publicEdKey: Data?
    let supportsDSA: Bool
    let archiveFileAttributes: [FileAttributeKey: Any]
    var deltas: [DeltaUpdate]

    var dsaSignature: String?
    var edSignature: String?
    var downloadUrlPrefix: URL?

    init(version: String, shortVersion: String?, feedURL: URL?, minimumSystemVersion: String?, publicEdKey: String?, supportsDSA: Bool, appPath: URL, archivePath: URL) throws {
        self.version = version
        self._shortVersion = shortVersion
        self.feedURL = feedURL
        self.minimumSystemVersion = minimumSystemVersion ?? "10.7"
        self.archivePath = archivePath
        self.appPath = appPath
        self.supportsDSA = supportsDSA
        if let publicEdKey = publicEdKey {
            self.publicEdKey = Data(base64Encoded: publicEdKey)
        } else {
            self.publicEdKey = nil
        }
        self.archiveFileAttributes = try FileManager.default.attributesOfItem(atPath: self.archivePath.path)
        self.deltas = []
    }

    convenience init(fromArchive archivePath: URL, unarchivedDir: URL) throws {
        let resourceKeys = [URLResourceKey.typeIdentifierKey]
        let items = try FileManager.default.contentsOfDirectory(at: unarchivedDir, includingPropertiesForKeys: resourceKeys, options: .skipsHiddenFiles)

        let bundles = items.filter({
            if let resourceValues = try? $0.resourceValues(forKeys: Set(resourceKeys)) {
                return UTTypeConformsTo(resourceValues.typeIdentifier! as CFString, kUTTypeBundle)
            } else {
                return false
            }
        })
        if bundles.count > 0 {
            if bundles.count > 1 {
                throw makeError(code: .unarchivingError, "Too many bundles in \(unarchivedDir.path) \(bundles)")
            }

            let appPath = bundles[0]
            guard let infoPlist = NSDictionary(contentsOf: appPath.appendingPathComponent("Contents/Info.plist")) else {
                throw makeError(code: .unarchivingError, "No plist \(appPath.path)")
            }
            guard let version = infoPlist[kCFBundleVersionKey] as? String else {
                throw makeError(code: .unarchivingError, "No Version \(kCFBundleVersionKey as String? ?? "missing kCFBundleVersionKey") \(appPath)")
            }
            let shortVersion = infoPlist["CFBundleShortVersionString"] as? String
            let publicEdKey = infoPlist[SUPublicEDKeyKey] as? String
            let supportsDSA = infoPlist[SUPublicDSAKeyKey] != nil || infoPlist[SUPublicDSAKeyFileKey] != nil

            var feedURL: URL?
            if let feedURLStr = infoPlist["SUFeedURL"] as? String {
                feedURL = URL(string: feedURLStr)
                if feedURL?.pathExtension == "php" {
                    feedURL = feedURL!.deletingLastPathComponent()
                    feedURL = feedURL!.appendingPathComponent("appcast.xml")
                }
            }

            try self.init(version: version,
                           shortVersion: shortVersion,
                           feedURL: feedURL,
                           minimumSystemVersion: infoPlist["LSMinimumSystemVersion"] as? String,
                           publicEdKey: publicEdKey,
                           supportsDSA: supportsDSA,
                           appPath: appPath,
                           archivePath: archivePath)
        } else {
            throw makeError(code: .missingUpdateError, "No supported items in \(unarchivedDir) \(items) [note: only .app bundles are supported]")
        }
    }

    var shortVersion: String {
        return self._shortVersion ?? self.version
    }

    var description: String {
        return "\(self.archivePath) \(self.version)"
    }

    var archiveURL: URL? {
        guard let escapedFilename = self.archivePath.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        if let downloadUrlPrefix = self.downloadUrlPrefix {
            // if a download url prefix was given use this one
            return URL(string: escapedFilename, relativeTo: downloadUrlPrefix)
        } else if let relativeFeedUrl = self.feedURL {
            return URL(string: escapedFilename, relativeTo: relativeFeedUrl)
        }
        return URL(string: escapedFilename)
    }

    var pubDate: String {
        let date = self.archiveFileAttributes[.creationDate] as! Date
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss ZZ"
        return formatter.string(from: date)
    }

    var fileSize: Int64 {
        return (self.archiveFileAttributes[.size] as! NSNumber).int64Value
    }

    private var releaseNotesPath: URL? {
        var basename = self.archivePath.deletingPathExtension()
        if basename.pathExtension == "tar" { // tar.gz
            basename = basename.deletingPathExtension()
        }
        let releaseNotes = basename.appendingPathExtension("html")
        if !FileManager.default.fileExists(atPath: releaseNotes.path) {
            return nil
        }
        return releaseNotes
    }

    private func getReleaseNotesAsHTMLFragment(_ path: URL) -> String?  {
        if let html = try? String(contentsOf: path) {
            if html.utf8.count < 1000 &&
                !html.localizedCaseInsensitiveContains("<!DOCTYPE") &&
                !html.localizedCaseInsensitiveContains("<body") {
                return html
            }
        }
        return nil
    }

    var releaseNotesHTML: String? {
        if let path = self.releaseNotesPath {
            return self.getReleaseNotesAsHTMLFragment(path)
        }
        return nil
    }

    var releaseNotesURL: URL? {
        guard let path = self.releaseNotesPath else {
            return nil
        }
        // The file is already used as inline description
        if self.getReleaseNotesAsHTMLFragment(path) != nil {
            return nil
        }
        guard let escapedFilename = path.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        if let relative = self.feedURL {
            return URL(string: escapedFilename, relativeTo: relative)
        }
        return URL(string: escapedFilename)
    }

    func localizedReleaseNotes() -> [(String, URL)] {
        let fileManager = FileManager.default
        var basename = archivePath.deletingPathExtension()
        if basename.pathExtension == "tar" {
            basename = basename.deletingPathExtension()
        }
        var localizedReleaseNotes = [(String, URL)]()
        for languageCode in Locale.isoLanguageCodes {
            let localizedReleaseNoteURL = basename
                .appendingPathExtension(languageCode)
                .appendingPathExtension("html")
            if fileManager.fileExists(atPath: localizedReleaseNoteURL.path) {
                localizedReleaseNotes.append((languageCode, localizedReleaseNoteURL))
            }
        }
        return localizedReleaseNotes
    }

    let mimeType = "application/octet-stream"
}
