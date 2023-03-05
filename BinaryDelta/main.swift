//
//  main.swift
//  BinaryDelta
//
//  Created by Mayur Pawashe on 1/3/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

import Foundation
import ArgumentParser

// Create a patch from an old and new bundle
struct Create: ParsableCommand {
    @Option(name: .long, help: ArgumentHelp("The major version of the patch to generate. Defaults to the latest stable version. Older versions will need to be specified for updating from applications using older versions of Sparkle.", valueName: "version"))
    var version: Int = Int(SUBinaryDeltaMajorVersionDefault.rawValue)
    
    @Flag(name: .customLong("verbose"), help: ArgumentHelp("Enable logging of the changes being archived into the generated patch."))
    var verbose: Bool = false
    
    @Option(name: .long, help: ArgumentHelp(COMPRESSION_METHOD_ARGUMENT_DESCRIPTION, valueName: "compression"))
    var compression: String = "default"
    
    @Option(name: .long, help: .hidden)
    var compressionLevel: UInt8 = 0
    
    @Argument(help: ArgumentHelp("Path to original bundle to create a patch from."))
    var beforeTree: String
    
    @Argument(help: ArgumentHelp("Path to new bundle to create a patch from."))
    var afterTree: String
    
    @Argument(help: ArgumentHelp("Path to new patch file to create."))
    var patchFile: String
        
    func validate() throws {
        var validCompression: ObjCBool = false
        let compressionMode = deltaCompressionModeFromDescription(compression, &validCompression)
        guard validCompression.boolValue else {
            fputs("Error: unrecognized compression \(compression)\n", stderr)
            throw ExitCode(1)
        }
        
        switch compressionMode {
        case SPUDeltaCompressionModeDefault:
            fallthrough
        case .none:
            guard compressionLevel == 0 else {
                fputs("Error: compression level must be 0 for compression \(compression)\n", stderr)
                throw ExitCode(1)
            }
            break
        case .bzip2:
            guard compressionLevel >= 0 && compressionLevel <= 9 else {
                fputs("Error: compression level \(compressionLevel) is not valid.\n", stderr)
                throw ExitCode(1)
            }
            break
        case .LZMA:
            fallthrough
        case .LZFSE:
            fallthrough
        case .LZ4:
            fallthrough
        case .ZLIB:
            guard version >= 3 else {
                fputs("Error: version \(version) patch files do not support compression \(compression)\n", stderr)
                throw ExitCode(1)
            }
            
            guard compressionLevel == 0 else {
                fputs("Error: compression level provided must be 0 for compression \(compression)\n", stderr)
                throw ExitCode(1)
            }
            break
        @unknown default:
            fputs("Error: unrecognized compression \(compression)\n", stderr)
            throw ExitCode(1)
        }
        
        guard version >= SUBinaryDeltaMajorVersionFirst.rawValue else {
            fputs("Error: version provided \(version) is not valid.\n", stderr)
            throw ExitCode(1)
        }
        
        guard version >= SUBinaryDeltaMajorVersionFirstSupported.rawValue else {
            fputs("Error: creating version \(version) patches is no longer supported.\n", stderr)
            throw ExitCode(1)
        }
        
        guard version <= SUBinaryDeltaMajorVersionLatest.rawValue else {
            fputs("Error: this program is too old to create a version \(version) patch, or the version number provided is invalid.\n", stderr)
            throw ExitCode(1)
        }
        
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: beforeTree, isDirectory: &isDirectory) || !isDirectory.boolValue {
            fputs("Error: before-tree must be a directory\n", stderr)
            throw ExitCode(1)
        }
        
        if !fileManager.fileExists(atPath: afterTree, isDirectory: &isDirectory) || !isDirectory.boolValue {
            fputs("Error: after-tree must be a directory\n", stderr)
            throw ExitCode(1)
        }
    }
    
    func run() throws {
        let compressionMode = deltaCompressionModeFromDescription(compression, nil)
        
        guard let majorDeltaVersion = SUBinaryDeltaMajorVersion(rawValue: UInt16(version)) else {
            // We shouldn't reach here
            fputs("Error: failed to retrieve major version from provided version: \(version)\n", stderr)
            throw ExitCode(1)
        }
        
        var createDiffError: NSError? = nil
        if !createBinaryDelta(beforeTree, afterTree, patchFile, majorDeltaVersion, compressionMode, compressionLevel, verbose, &createDiffError) {
            if let error = createDiffError {
                fputs("\(error.localizedDescription)\n", stderr)
            } else {
                fputs("Error: Failed to create patch due to unknown reason.\n", stderr)
            }
            throw ExitCode(1)
        }
    }
}

// Apply a patch from an old bundle to generate a new bundle
struct Apply: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Apply a patch against an original bundle to generate a new bundle.")
    
    @Flag(name: .customLong("verbose"), help: ArgumentHelp("Enable logging of changes being applied from the patch."))
    var verbose: Bool = false
    
    @Argument(help: ArgumentHelp("Path to original bundle to patch."))
    var beforeTree: String
    
    @Argument(help: ArgumentHelp("Path to new bundle to create."))
    var afterTree: String
    
    @Argument(help: ArgumentHelp("Path to patch file to apply."))
    var patchFile: String
    
    func validate() throws {
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: beforeTree, isDirectory: &isDirectory) || !isDirectory.boolValue {
            fputs("Error: before-tree must be a directory\n", stderr)
            throw ExitCode(1)
        }
        
        if !fileManager.fileExists(atPath: patchFile, isDirectory: &isDirectory) || isDirectory.boolValue {
            fputs("Error: patch-file must be a file\n", stderr)
            throw ExitCode(1)
        }
    }
    
    func run() throws {
        var applyDiffError: NSError?
        if (!applyBinaryDelta(beforeTree, afterTree, patchFile, verbose, { _ in }, &applyDiffError)) {
            if let error = applyDiffError {
                fputs("\(error.localizedDescription)\n", stderr)
            } else {
                fputs("Error: patch failed to apply for unknown reason\n", stderr)
            }
            throw ExitCode(1)
        }
    }
}

// Output information for BinaryDelta or from a patch file
struct Info: ParsableCommand {
    @Argument(help: ArgumentHelp("Path to patch file to extract information from."))
    var patchFile : String?
    
    func run() throws {
        if let patchFile = patchFile {
            // Print version of patch file
            var header: SPUDeltaArchiveHeader? = nil
            let archive = SPUDeltaArchiveReadPatchAndHeader(patchFile, &header)
            if let error = archive.error {
                fputs("Error: Unable to open patch \(patchFile): \(error.localizedDescription)\n", stderr)
                throw ExitCode(1)
            }
            
            if let header = header {
                if header.majorVersion < SUBinaryDeltaMajorVersionFirst.rawValue {
                    fputs("Error: major version \(header.majorVersion) is invalid.\n", stderr)
                    throw ExitCode(1)
                }
                
                fputs("Patch version \(header.majorVersion).\(header.minorVersion)", stdout)
                
                // Print out compression info only if it's available
                // We can't get compression info from version 2 files
                if header.compression != SPUDeltaCompressionModeDefault, let compressionDescription = deltaCompressionStringFromMode(header.compression) {
                    fputs(" using \(compressionDescription) compression", stdout)
                    
                    // Compression level isn't available or applicable for all formats
                    if header.compressionLevel != 0 {
                        fputs(" with level \(header.compressionLevel)", stdout)
                    }
                }
                
                fputs("\n", stdout)
            } else {
                fputs("Error: Failed to retrieve header due to unknown reason.\n", stderr)
                throw ExitCode(1)
            }
        } else {
            // Print version of program
            fputs("BinaryDelta version \(SUBinaryDeltaMajorVersionLatest.rawValue).\(latestMinorVersionForMajorVersion(SUBinaryDeltaMajorVersionLatest))\n", stdout)
        }
    }
}

struct BinaryDelta: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "BinaryDelta", abstract: "Create and apply small and efficient delta patches between an old and new version of a bundle.", subcommands: [Create.self, Apply.self, Info.self])
}

DispatchQueue.global().async(execute: {
    BinaryDelta.main()
    CFRunLoopStop(CFRunLoopGetMain())
})
CFRunLoopRun()
