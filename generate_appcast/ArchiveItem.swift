//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation

class DeltaUpdate {
    let fromVersion: String;
    let archivePath: URL;
    var dsaSignature: String?;

    init(fromVersion: String, archivePath: URL) {
        self.archivePath = archivePath;
        self.fromVersion = fromVersion;
    }

    var fileSize : Int64 {
        let archiveFileAttributes = try! FileManager.default.attributesOfItem(atPath: self.archivePath.path);
        return (archiveFileAttributes[.size] as! NSNumber).int64Value;
    }

    class func create(from: ArchiveItem, to: ArchiveItem, archivePath: URL) throws -> DeltaUpdate {
        var applyDiffError: NSError? = nil;

        if (!createBinaryDelta(from.appPath.path, to.appPath.path, archivePath.path, .beigeMajorVersion, false, &applyDiffError)) {
            throw applyDiffError!;
        }

        return DeltaUpdate(fromVersion: from.version, archivePath: archivePath);
    }
}

class ArchiveItem: CustomStringConvertible {
    let version: String;
    let _shortVersion: String?;
    let minimumSystemVersion: String;
    let archivePath: URL;
    let appPath: URL;
    let feedURL: URL?;
    let archiveFileAttributes: [FileAttributeKey:Any];
    var deltas: [DeltaUpdate];

    var dsaSignature: String?;

    init(version: String, shortVersion: String?, feedURL: URL?, minimumSystemVersion: String?, appPath: URL, archivePath: URL) throws {
        self.version = version;
        self._shortVersion = shortVersion;
        self.feedURL = feedURL;
        self.minimumSystemVersion = minimumSystemVersion ?? "10.7";
        self.archivePath = archivePath;
        self.appPath = appPath;
        self.archiveFileAttributes = try FileManager.default.attributesOfItem(atPath: self.archivePath.path);
        self.deltas = [];
    }

    convenience init(fromArchive archivePath: URL, unarchivedDir: URL) throws {
        let items = try FileManager.default.contentsOfDirectory(atPath: unarchivedDir.path)
            .filter({ !$0.hasPrefix(".") })
            .map({ unarchivedDir.appendingPathComponent($0) })

        let apps = items.filter({ $0.pathExtension == "app" });
        if apps.count > 0 {
            if apps.count > 1 {
                throw makeError(code: .unarchivingError, "Too many apps in \(unarchivedDir.path) \(apps)");
            }

            let appPath = apps[0];
            guard let infoPlist = NSDictionary(contentsOf: appPath.appendingPathComponent("Contents/Info.plist")) else {
                throw makeError(code: .unarchivingError, "No plist \(appPath.path)");
            }
            guard let version = infoPlist[kCFBundleVersionKey] as? String else {
                throw makeError(code: .unarchivingError, "No Version \(kCFBundleVersionKey) \(appPath)");
            }
            let shortVersion = infoPlist["CFBundleShortVersionString"] as? String;

            var feedURL:URL? = nil;
            if let feedURLStr = infoPlist["SUFeedURL"] as? String {
                feedURL = URL(string: feedURLStr);
            }

            try self.init(version: version,
                           shortVersion: shortVersion,
                           feedURL: feedURL,
                           minimumSystemVersion: infoPlist["LSMinimumSystemVersion"] as? String,
                           appPath: appPath,
                           archivePath: archivePath);
        } else {
            throw makeError(code: .missingUpdateError, "No supported items in \(unarchivedDir) \(items) [note: only .app bundles are supported]");
        }
    }

    var shortVersion: String {
        return self._shortVersion ?? self.version;
    }

    var description : String {
        return "\(self.archivePath) \(self.version)"
    }

    var archiveURL: URL? {
        guard let escapedFilename = self.archivePath.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil;
        }
        if let relative = self.feedURL {
            return URL(string: escapedFilename, relativeTo: relative)
        }
        return URL(string: escapedFilename)
    }

    var pubDate : String {
        let date = self.archiveFileAttributes[.creationDate] as! Date;
        let formatter = DateFormatter();
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss ZZ";
        return formatter.string(from: date);
    }

    var fileSize : Int64 {
        return (self.archiveFileAttributes[.size] as! NSNumber).int64Value;
    }
    
    private var releaseNotesPath : URL? {
        var basename = self.archivePath.deletingPathExtension();
        if basename.pathExtension == "tar" { // tar.gz
            basename = basename.deletingPathExtension();
        }
        let releaseNotes = basename.appendingPathExtension("html");
        if !FileManager.default.fileExists(atPath: releaseNotes.path) {
            return nil;
        }
        return releaseNotes;
    }

    private func getReleaseNotesAsHTMLFragment(_ path: URL) -> String?  {
        if let html = try? String(contentsOf: path) {
            if html.utf8.count < 1000 &&
                !html.localizedCaseInsensitiveContains("<!DOCTYPE") &&
                !html.localizedCaseInsensitiveContains("<body") {
                return html;
            }
        }
        return nil;
    }

    var releaseNotesHTML : String? {
        if let path = self.releaseNotesPath {
            return self.getReleaseNotesAsHTMLFragment(path);
        }
        return nil;
    }

    var releaseNotesURL : URL? {
        guard let path = self.releaseNotesPath else {
            return nil;
        }
        // The file is already used as inline description
        if self.getReleaseNotesAsHTMLFragment(path) != nil {
            return nil;
        }
        guard let escapedFilename = path.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil;
        }
        if let relative = self.feedURL {
            return URL(string: escapedFilename, relativeTo: relative)
        }
        return URL(string: escapedFilename)
    }

    let mimeType = "application/octet-stream";
}
