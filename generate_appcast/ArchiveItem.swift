//
//  Created by Kornel on 22/12/2016.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers

struct UpdateBranch: Hashable {
    let minimumUpdateVersion: String?
    let minimumSystemVersion: String?
    let maximumSystemVersion: String?
    let minimumAutoupdateVersion: String?
    let hardwareRequirements: String?
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
    let hardwareRequirements: String?
    let frameworkVersion: String?
    let sparkleExecutableFileSize: Int?
    let sparkleLocales: String?
    let archivePath: URL
    let appPath: URL
    let feedURL: URL?
    let publicEdKey: Data?
    let supportsDSA: Bool
    let requiresSignedAppcast: Bool
    let archiveFileAttributes: [FileAttributeKey: Any]
    var deltas: [DeltaUpdate]

#if GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
    var dsaSignature: String?
#endif
    var edSignature: String?
    var downloadUrlPrefix: URL?
    var releaseNotesURLPrefix: URL?
    var signingError: Error?
    
    @available(macOS 10.15.4, *)
    private static func binaryContainsPreARMSlice(_ fileURL: URL) -> Bool? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        
        defer {
            try? fileHandle.close()
        }
        
        // First, read just enough bytes to determine the magic number (4 bytes)
        let MAGIC_SIZE = 4
        guard let magicData = try? fileHandle.read(upToCount: MAGIC_SIZE),
              magicData.count == MAGIC_SIZE else {
            return nil
        }
        
        let preARMSlices: [cpu_type_t] = [CPU_TYPE_X86_64, CPU_TYPE_I386, CPU_TYPE_POWERPC, CPU_TYPE_POWERPC64]
        
        // Read magic number
        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Check if this is a fat binary
        if magic == FAT_CIGAM || magic == FAT_CIGAM_64 {
            // For fat binaries, we need to read the rest of the fat_header to get the number of architectures
            guard let remainingHeaderData = try? fileHandle.read(upToCount: MemoryLayout<fat_header>.size - MAGIC_SIZE),
                  remainingHeaderData.count == MemoryLayout<fat_header>.size - MAGIC_SIZE else {
                return nil
            }
            
            // Read number of architectures
            let nfat_arch = remainingHeaderData.withUnsafeBytes {
                let value = $0.load(fromByteOffset: 0, as: UInt32.self)
                return value.bigEndian
            }
            
            let is64BitMagic = (magic == FAT_CIGAM_64)
            
            let fatArchSize = is64BitMagic ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size
            
            // Read each architecture header
            for i in 0..<Int(nfat_arch) {
                let offset = MemoryLayout<fat_header>.size + (i * fatArchSize)
                
                // We need to seek from the beginning of the file
                guard let _ = try? fileHandle.seek(toOffset: UInt64(offset)),
                      let archHeaderData = try? fileHandle.read(upToCount: fatArchSize),
                      archHeaderData.count >= fatArchSize else {
                    continue
                }
                
                let cputype = archHeaderData.withUnsafeBytes {
                    let value = $0.load(as: Int32.self)
                    return Int32(bigEndian: value)
                }
                
                if preARMSlices.contains(cputype) {
                    return true
                }
            }
            
            return false
        } else if magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64 {
            // For Mach-O binaries, we need to read the rest of the mach_header to get CPU type
            let is64BitMagic = (magic == MH_MAGIC_64 || magic == MH_CIGAM_64)
            let machHeaderSize = is64BitMagic ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
            
            // Read the rest of the header
            guard let remainingHeaderData = try? fileHandle.read(upToCount: machHeaderSize - MAGIC_SIZE),
                  remainingHeaderData.count == machHeaderSize - MAGIC_SIZE else {
                return nil
            }
            
            let reversedEndian = (magic == MH_CIGAM || magic == MH_CIGAM_64)
            
            let cputype = remainingHeaderData.withUnsafeBytes {
                let value = $0.load(fromByteOffset: 0, as: Int32.self)
                return reversedEndian ? Int32(bigEndian: value) : Int32(littleEndian: value)
            }
            
            return preARMSlices.contains(cputype)
        } else {
            return nil
        }
    }

    init(version: String, shortVersion: String?, feedURL: URL?, requiresSignedAppcast: Bool, minimumSystemVersion: String?, hardwareRequirements: String?, frameworkVersion: String?, sparkleExecutableFileSize: Int?, sparkleLocales: String?, publicEdKey: String?, supportsDSA: Bool, appPath: URL, archivePath: URL) throws {
        self.version = version
        self._shortVersion = shortVersion
        self.feedURL = feedURL
        self.requiresSignedAppcast = requiresSignedAppcast
        self.minimumSystemVersion = minimumSystemVersion ?? "10.13"
        self.hardwareRequirements = hardwareRequirements
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
            
            let requiresSignedAppcast: Bool
            if let requiresSignedAppcastValue = infoPlist[SURequireSignedFeedKey] as? Bool {
                requiresSignedAppcast = requiresSignedAppcastValue
            } else {
                requiresSignedAppcast = false
            }
            
            // Intel Macs shouldn't be supported on macOS 27+ and
            // we don't have any other hardware requirements except for arm64 right now
            var mayNeedHardwareRequirement = true
            let minimumSystemVersion = infoPlist["LSMinimumSystemVersion"] as? String
            if let minimumSystemVersion {
                let versionComparator = SUStandardVersionComparator()
                if versionComparator.compareVersion(minimumSystemVersion, toVersion: "27.0") != .orderedAscending {
                    mayNeedHardwareRequirement = false
                }
            }
            
            var hardwareRequirements: String? = nil
            if mayNeedHardwareRequirement {
                if #available(macOS 10.15.4, *) {
                    if let executableName = infoPlist[kCFBundleExecutableKey as String] as? String {
                        let executablePath = appPath.appendingPathComponent("Contents/MacOS/\(executableName)")
                        if let containsPreARMSlice = Self.binaryContainsPreARMSlice(executablePath), !containsPreARMSlice {
                            hardwareRequirements = SUAppcastElementHardwareRequirementARM64
                        }
                    }
                }
            }
            
            var frameworkVersion: String? = nil
            let sparkleExecutableFileSize: Int?
            let sparkleLocales: String?
            do {
                let fileManager = FileManager.default
                
                let frameworksURL: URL?
                let canonicalFrameworksURL = appPath.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
                if fileManager.fileExists(atPath: canonicalFrameworksURL.path) {
                    frameworksURL = canonicalFrameworksURL
                } else {
                    // The framework may be inside another framework or plug-in. Find it.
                    if let enumerator = fileManager.enumerator(at: appPath, includingPropertiesForKeys: [], options: [.skipsHiddenFiles], errorHandler: nil) {
                        var foundFrameworksURL: URL?
                        
                        for case let fileURL as URL in enumerator {
                            let name = fileURL.lastPathComponent
                            
                            // Skip Resources in bundles entirely because frameworks shouldn't be in there and we don't want to pay the cost of scanning in there
                            guard name != "Resources" else {
                                enumerator.skipDescendants()
                                continue
                            }
                            
                            if name == "Sparkle.framework" {
                                foundFrameworksURL = fileURL
                                break
                            }
                        }
                        
                        frameworksURL = foundFrameworksURL
                    } else {
                        frameworksURL = nil
                    }
                }
                
                if let frameworksURL = frameworksURL {
                    let resourcesURL = frameworksURL.appendingPathComponent("Resources").resolvingSymlinksInPath()
                    
                    if let frameworkInfoPlist = NSDictionary(contentsOf: resourcesURL.appendingPathComponent("Info.plist")) {
                        frameworkVersion = frameworkInfoPlist[kCFBundleVersionKey as String] as? String
                    }
                    
                    let frameworkExecutableURL = frameworksURL.appendingPathComponent("Sparkle").resolvingSymlinksInPath()
                    do {
                        let resourceValues = try frameworkExecutableURL.resourceValues(forKeys: [.fileSizeKey])
                        
                        sparkleExecutableFileSize = resourceValues.fileSize
                    } catch {
                        sparkleExecutableFileSize = nil
                    }
                    
                    do {
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
                          requiresSignedAppcast: requiresSignedAppcast,
                          minimumSystemVersion: minimumSystemVersion,
                          hardwareRequirements: hardwareRequirements,
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

    var releaseNotesPath: URL? {
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
        
        let markdownReleaseNotes = basename.appendingPathExtension("md")
        if FileManager.default.fileExists(atPath: markdownReleaseNotes.path) {
            return markdownReleaseNotes
        }
        
        let markdownSecondaryReleaseNotes = basename.appendingPathExtension("markdown")
        if FileManager.default.fileExists(atPath: markdownSecondaryReleaseNotes.path) {
            return markdownSecondaryReleaseNotes
        }
        
        return nil
    }

    private func getReleaseNotesAsFragment(_ path: URL, _ embedReleaseNotesAlways: Bool) -> (content: String, format: String)?  {
        guard let data = try? Data(contentsOf: path) else {
            return nil
        }
        
        let contentData: Data
        let format: String
        let pathExtension = path.pathExtension
        switch pathExtension {
        case "txt", "TXT":
            format = "plain-text"
            contentData = data
        case "md", "MD", "markdown", "MARKDOWN":
            format = "markdown"
            contentData = SPUExtractReleaseNotesContent(data)
        default:
            format = "html"
            contentData = SPUExtractReleaseNotesContent(data)
        }
        
        if embedReleaseNotesAlways {
            guard let contentString = String(data: contentData, encoding: .utf8) else {
                print("Error: failed to read release notes as UTF8 string: \(path.lastPathComponent)")
                return nil
            }
            
            return (contentString, format)
        } else if format == "html", let contentString = String(data: contentData, encoding: .utf8), !contentString.localizedCaseInsensitiveContains("<!DOCTYPE") && !contentString.localizedCaseInsensitiveContains("<body")  {
            // HTML fragments should always be embedded
            return (contentString, format)
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
    
    func releaseNotesURL(releaseNotesPath: URL, embedReleaseNotesAlways: Bool) -> URL? {
        // The file is already used as inline description
        if self.getReleaseNotesAsFragment(releaseNotesPath, embedReleaseNotesAlways) != nil {
            return nil
        }
        return self.releaseNoteURL(for: releaseNotesPath.lastPathComponent)
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

    func localizedReleaseNotes() -> [(String, URL, URL)] {
        var basename = archivePath.deletingPathExtension()
        if basename.pathExtension == "tar" {
            basename = basename.deletingPathExtension()
        }
        var localizedReleaseNotes = [(String, URL, URL)]()
        for languageCode in Locale.isoLanguageCodes {
            let baseLocalizedReleaseNoteURL = basename
                .appendingPathExtension(languageCode)
            
            let htmlLocalizedReleaseNoteURL = baseLocalizedReleaseNoteURL.appendingPathExtension("html")
            let plainTextLocalizedReleaseNoteURL = baseLocalizedReleaseNoteURL.appendingPathExtension("txt")
            let markdownLocalizedReleaseNoteURL = baseLocalizedReleaseNoteURL.appendingPathExtension("md")
            let markdownSecondaryLocalizedReleaseNoteURL = baseLocalizedReleaseNoteURL.appendingPathExtension("markdown")
            
            let localizedReleaseNoteURL: URL?
            
            if (try? htmlLocalizedReleaseNoteURL.checkResourceIsReachable()) ?? false {
                localizedReleaseNoteURL = htmlLocalizedReleaseNoteURL
            } else if (try? plainTextLocalizedReleaseNoteURL.checkResourceIsReachable()) ?? false {
                localizedReleaseNoteURL = plainTextLocalizedReleaseNoteURL
            } else if (try? markdownLocalizedReleaseNoteURL.checkResourceIsReachable()) ?? false {
                localizedReleaseNoteURL = markdownLocalizedReleaseNoteURL
            } else if (try? markdownSecondaryLocalizedReleaseNoteURL.checkResourceIsReachable()) ?? false {
                localizedReleaseNoteURL = markdownSecondaryLocalizedReleaseNoteURL
            } else {
                localizedReleaseNoteURL = nil
            }
            
            if let localizedReleaseNoteURL = localizedReleaseNoteURL,
               let localizedReleaseNoteRemoteURL = self.releaseNoteURL(for: localizedReleaseNoteURL.lastPathComponent)
            {
                localizedReleaseNotes.append((languageCode, localizedReleaseNoteRemoteURL, localizedReleaseNoteURL))
            }
        }
        return localizedReleaseNotes
    }

    let mimeType = "application/octet-stream"
}
