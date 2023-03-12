//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers

struct UpdateBranch: Hashable {
    let minimumSystemVersion: String?
    let maximumSystemVersion: String?
    let minimumAutoupdateVersion: String?
    let channel: String?
}

class DeltaUpdate {
    let fromVersion: String
    let archivePath: URL
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
    var dsaSignature: String?
#endif
    var edSignature: String?
    let sparkleExecutableFileSize: Int?
    let sparkleLocales: String?

    init(fromVersion: String, archivePath: URL, sparkleExecutableFileSize: Int?, sparkleLocales: String?) {
        self.archivePath = archivePath
        self.fromVersion = fromVersion
        self.sparkleExecutableFileSize = sparkleExecutableFileSize
        self.sparkleLocales = sparkleLocales
    }

    var fileSize: Int64 {
        let archiveFileAttributes = try! FileManager.default.attributesOfItem(atPath: self.archivePath.path)
        return (archiveFileAttributes[.size] as! NSNumber).int64Value
    }

    class func create(from: ArchiveItem, to: ArchiveItem, deltaVersion: SUBinaryDeltaMajorVersion, deltaCompressionMode: SPUDeltaCompressionMode, deltaCompressionLevel: UInt8, archivePath: URL) throws -> DeltaUpdate {
        var createDiffError: NSError?

        if !createBinaryDelta(from.appPath.path, to.appPath.path, archivePath.path, deltaVersion, deltaCompressionMode, deltaCompressionLevel, false, &createDiffError) {
            throw createDiffError!
        }
        
        // Ensure applying the diff also succeeds
        let fileManager = FileManager.default
        
        let tempApplyToPath = to.appPath.deletingLastPathComponent().appendingPathComponent(".temp_" + to.appPath.lastPathComponent)
        let _ = try? fileManager.removeItem(at: tempApplyToPath)
        
        var applyDiffError: NSError?
        if !applyBinaryDelta(from.appPath.path, tempApplyToPath.path, archivePath.path, false, { _ in
        }, &applyDiffError) {
            let _ = try? fileManager.removeItem(at: archivePath)
            throw applyDiffError!
        }
        
        let _ = try? fileManager.removeItem(at: tempApplyToPath)

        return DeltaUpdate(fromVersion: from.version, archivePath: archivePath, sparkleExecutableFileSize: from.sparkleExecutableFileSize, sparkleLocales: from.sparkleLocales)
    }
}

class ArchiveItem: CustomStringConvertible {
    let version: String
    // swiftlint:disable identifier_name
    let _shortVersion: String?
    let minimumSystemVersion: String
    let frameworkVersion: String?
    let sparkleExecutableFileSize: Int?
    let sparkleLocales: String?
    let archivePath: URL
    let appPath: URL
    let feedURL: URL?
    let publicEdKey: Data?
    let supportsDSA: Bool
    let archiveFileAttributes: [FileAttributeKey: Any]
    var deltas: [DeltaUpdate]

#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
    var dsaSignature: String?
#endif
    var edSignature: String?
    var downloadUrlPrefix: URL?
    var releaseNotesURLPrefix: URL?
    var signingError: Error?

    init(version: String, shortVersion: String?, feedURL: URL?, minimumSystemVersion: String?, frameworkVersion: String?, sparkleExecutableFileSize: Int?, sparkleLocales: String?, publicEdKey: String?, supportsDSA: Bool, appPath: URL, archivePath: URL) throws {
        self.version = version
        self._shortVersion = shortVersion
        self.feedURL = feedURL
        self.minimumSystemVersion = minimumSystemVersion ?? "10.13"
        self.frameworkVersion = frameworkVersion
        self.sparkleExecutableFileSize = sparkleExecutableFileSize
        self.sparkleLocales = sparkleLocales
        self.archivePath = archivePath
        self.appPath = appPath
        self.supportsDSA = supportsDSA
        if let publicEdKey = publicEdKey {
            self.publicEdKey = Data(base64Encoded: publicEdKey)
        } else {
            self.publicEdKey = nil
        }
        let path = (self.archivePath.path as NSString).resolvingSymlinksInPath
        self.archiveFileAttributes = try FileManager.default.attributesOfItem(atPath: path)
        self.deltas = []
    }

    convenience init(fromArchive archivePath: URL, unarchivedDir: URL, validateBundle: Bool, disableNestedCodeCheck: Bool) throws {
        let resourceKeys: [URLResourceKey]
        if #available(macOS 11, *) {
            resourceKeys = [.contentTypeKey]
        } else {
            resourceKeys = [.typeIdentifierKey]
        }
        let items = try FileManager.default.contentsOfDirectory(at: unarchivedDir, includingPropertiesForKeys: resourceKeys, options: .skipsHiddenFiles)

        let bundles = items.filter({
            if let resourceValues = try? $0.resourceValues(forKeys: Set(resourceKeys)) {
                if #available(macOS 11, *) {
                    return resourceValues.contentType!.conforms(to: .bundle)
                } else {
                    return UTTypeConformsTo(resourceValues.typeIdentifier! as CFString, kUTTypeBundle)
                }
            } else {
                return false
            }
        })
        if bundles.count > 0 {
            if bundles.count > 1 {
                throw makeError(code: .unarchivingError, "Too many bundles in \(unarchivedDir.path) \(bundles)")
            }

            let appPath = bundles[0]
            
            // If requested to validate the bundle, ensure it is properly signed
            if validateBundle && SUCodeSigningVerifier.bundle(atURLIsCodeSigned: appPath) {
                try SUCodeSigningVerifier.codeSignatureIsValid(atBundleURL: appPath, checkNestedCode: !disableNestedCodeCheck)
            }
            
            guard let infoPlist = NSDictionary(contentsOf: appPath.appendingPathComponent("Contents/Info.plist")) else {
                throw makeError(code: .unarchivingError, "No plist \(appPath.path)")
            }
            guard let version = infoPlist[kCFBundleVersionKey!] as? String else {
                throw makeError(code: .unarchivingError, "No Version \(kCFBundleVersionKey as String? ?? "missing kCFBundleVersionKey") \(appPath)")
            }
            let shortVersion = infoPlist["CFBundleShortVersionString"] as? String
            let publicEdKey = infoPlist[SUPublicEDKeyKey] as? String
#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
            let supportsDSA = infoPlist[SUPublicDSAKeyKey] != nil || infoPlist[SUPublicDSAKeyFileKey] != nil
#else
            let supportsDSA = false
#endif

            var feedURL: URL?
            if let feedURLStr = infoPlist["SUFeedURL"] as? String {
                feedURL = URL(string: feedURLStr)
                if feedURL?.pathExtension == "php" {
                    feedURL = feedURL!.deletingLastPathComponent()
                    feedURL = feedURL!.appendingPathComponent("appcast.xml")
                }
            }
            
            var frameworkVersion: String? = nil
            let sparkleExecutableFileSize: Int?
            let sparkleLocales: String?
            do {
                let canonicalFrameworksURL = appPath.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
                
                let frameworksURL: URL?
                let usingLegacySparkleCore: Bool
                if !FileManager.default.fileExists(atPath: canonicalFrameworksURL.path) {
                    // Try legacy SparkleCore framework that was shipping in early 2.0 betas
                    let sparkleCoreFrameworksURL = appPath.appendingPathComponent("Contents/Frameworks/SparkleCore.framework")
                    if FileManager.default.fileExists(atPath: sparkleCoreFrameworksURL.path) {
                        frameworksURL = sparkleCoreFrameworksURL
                        usingLegacySparkleCore = true
                    } else {
                        frameworksURL = nil
                        usingLegacySparkleCore = false
                    }
                } else {
                    frameworksURL = canonicalFrameworksURL
                    usingLegacySparkleCore = false
                }
                
                if let frameworksURL = frameworksURL {
                    let resourcesURL = frameworksURL.appendingPathComponent("Resources").resolvingSymlinksInPath()
                    
                    if let frameworkInfoPlist = NSDictionary(contentsOf: resourcesURL.appendingPathComponent("Info.plist")) {
                        frameworkVersion = frameworkInfoPlist[kCFBundleVersionKey as String] as? String
                    }
                    
                    let frameworkExecutableURL = frameworksURL.appendingPathComponent(!usingLegacySparkleCore ? "Sparkle" : "SparkleCore").resolvingSymlinksInPath()
                    do {
                        let resourceValues = try frameworkExecutableURL.resourceValues(forKeys: [.fileSizeKey])
                        
                        sparkleExecutableFileSize = resourceValues.fileSize
                    } catch {
                        sparkleExecutableFileSize = nil
                    }
                    
                    do {
                        let fileManager = FileManager.default
                        let resourcesDirectoryContents = try fileManager.contentsOfDirectory(atPath: resourcesURL.path)
                        let localeExtension = ".lproj"
                        let localeExtensionCount = localeExtension.count
                        let maxLocalesToProcess = 7
                        var localesPresent: [String] = []
                        var localeIndex = 0
                        for filename in resourcesDirectoryContents {
                            guard filename.hasSuffix(localeExtension) else {
                                continue
                            }
                            
                            // English and Base directories are the least likely to be stripped,
                            // so let's not bother recording them.
                            guard filename != "en" && filename != "Base" else {
                                continue
                            }
                            
                            let locale = String(filename.dropLast(localeExtensionCount))
                            localesPresent.append(locale)
                            localeIndex += 1
                            
                            if localeIndex >= maxLocalesToProcess {
                                break
                            }
                        }
                        
                        if localesPresent.count > 0 {
                            sparkleLocales = localesPresent.joined(separator: ",")
                        } else {
                            sparkleLocales = nil
                        }
                    } catch {
                        sparkleLocales = nil
                    }
                } else {
                    sparkleExecutableFileSize = nil
                    sparkleLocales = nil
                }
            }

            try self.init(version: version,
                          shortVersion: shortVersion,
                          feedURL: feedURL,
                          minimumSystemVersion: infoPlist["LSMinimumSystemVersion"] as? String,
                          frameworkVersion: frameworkVersion,
                          sparkleExecutableFileSize: sparkleExecutableFileSize,
                          sparkleLocales: sparkleLocales,
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
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
        
        let htmlReleaseNotes = basename.appendingPathExtension("html")
        if FileManager.default.fileExists(atPath: htmlReleaseNotes.path) {
            return htmlReleaseNotes
        }
        
        let plainTextReleaseNotes = basename.appendingPathExtension("txt")
        if FileManager.default.fileExists(atPath: plainTextReleaseNotes.path) {
            return plainTextReleaseNotes
        }
        
        return nil
    }

    private func getReleaseNotesAsFragment(_ path: URL, _ embedReleaseNotesAlways: Bool) -> (content: String, format: String)?  {
        guard let content = try? String(contentsOf: path) else {
            return nil
        }
        
        let format = (path.pathExtension.caseInsensitiveCompare("txt") == .orderedSame) ? "plain-text" : "html"
        
        if embedReleaseNotesAlways {
            return (content, format)
        } else if path.pathExtension.caseInsensitiveCompare("html") == .orderedSame && !content.localizedCaseInsensitiveContains("<!DOCTYPE") && !content.localizedCaseInsensitiveContains("<body")  {
            // HTML fragments should always be embedded
            return (content, format)
        } else {
            return nil
        }
    }
    
    func releaseNotesContent(embedReleaseNotesAlways: Bool) -> (content: String, format: String)? {
        if let path = self.releaseNotesPath {
            return self.getReleaseNotesAsFragment(path, embedReleaseNotesAlways)
        }
        return nil
    }
    
    func releaseNotesURL(embedReleaseNotesAlways: Bool) -> URL? {
        guard let path = self.releaseNotesPath else {
            return nil
        }
        // The file is already used as inline description
        if self.getReleaseNotesAsFragment(path, embedReleaseNotesAlways) != nil {
            return nil
        }
        return self.releaseNoteURL(for: path.lastPathComponent)
    }
    
    func releaseNoteURL(for unescapedFilename: String) -> URL? {
        guard let escapedFilename = unescapedFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        if let releaseNotesURLPrefix = self.releaseNotesURLPrefix {
            // If a URL prefix for release notes was passed on the commandline, use it
            return URL(string: escapedFilename, relativeTo: releaseNotesURLPrefix)
        } else if let relativeURL = self.feedURL {
            return URL(string: escapedFilename, relativeTo: relativeURL)
        } else {
            return URL(string: escapedFilename)
        }
    }

    func localizedReleaseNotes() -> [(String, URL)] {
        var basename = archivePath.deletingPathExtension()
        if basename.pathExtension == "tar" {
            basename = basename.deletingPathExtension()
        }
        var localizedReleaseNotes = [(String, URL)]()
        for languageCode in Locale.isoLanguageCodes {
            let baseLocalizedReleaseNoteURL = basename
                .appendingPathExtension(languageCode)
            
            let htmlLocalizedReleaseNoteURL = baseLocalizedReleaseNoteURL.appendingPathExtension("html")
            let plainTextLocalizedReleaseNoteURL = baseLocalizedReleaseNoteURL.appendingPathExtension("txt")
            
            let localizedReleaseNoteURL: URL?
            
            if (try? htmlLocalizedReleaseNoteURL.checkResourceIsReachable()) ?? false {
                localizedReleaseNoteURL = htmlLocalizedReleaseNoteURL
            } else if (try? plainTextLocalizedReleaseNoteURL.checkResourceIsReachable()) ?? false {
                localizedReleaseNoteURL = plainTextLocalizedReleaseNoteURL
            } else {
                localizedReleaseNoteURL = nil
            }
            
            if let localizedReleaseNoteURL = localizedReleaseNoteURL,
               let localizedReleaseNoteRemoteURL = self.releaseNoteURL(for: localizedReleaseNoteURL.lastPathComponent)
            {
                localizedReleaseNotes.append((languageCode, localizedReleaseNoteRemoteURL))
            }
        }
        return localizedReleaseNotes
    }

    let mimeType = "application/octet-stream"
}
