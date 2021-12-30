//
//  SPUDeltaArchiveProtocol.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Attributes for an item we extract/write to the archive
typedef NS_ENUM(uint8_t, SPUDeltaFileAttributes) {
    SPUDeltaFileAttributesDelete = (1u << 0),
    SPUDeltaFileAttributesExtract = (1u << 1),
    SPUDeltaFileAttributesModifyPermissions = (1u << 2),
    SPUDeltaFileAttributesBinaryDiff = (1u << 3),
};

// A protocol for reading and writing binary delta patches
@protocol SPUDeltaArchiveProtocol <NSObject>

@property (nonatomic, readonly, class) BOOL maySupportSafeExtraction;

// Closes file for reading/writing, called in -dealloc if it's not called manually
- (void)close;

// For reading

// Retrieves metadata for the archive including major/minor version and expected bundle hashes
- (void)getMajorDeltaVersion:(nullable uint16_t *)outMajorDiffVersion minorDeltaVersion:(nullable uint16_t *)outMinorDiffVersion beforeTreeHash:(NSString * _Nullable __autoreleasing * _Nullable)outBeforeTreeHash afterTreeHash:(NSString * _Nullable __autoreleasing * _Nullable)outAfterTreeHash;

// Enumerate through items in the patch file and read the path, attributes, permissions (if permission attribute is available), and way to stop enumeration
- (BOOL)enumerateItems:(void (^)(const void *item, NSString *relativePath, SPUDeltaFileAttributes attributes, uint16_t permissions, BOOL *stop))itemHandler;

// Extract a file item from the patch file to a destination file
- (BOOL)extractItem:(const void *)item destination:(NSString *)destinationPath;

// For writing

// Set metadata for archive including major/minor version and expected bundle hashes
- (void)setMajorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(NSString *)beforeTreeHash afterTreeHash:(NSString *)afterTreeHash;

// Add item to patch file
// File path must be provided if there is a extract or binary delta attribute
// Permissions are used only if there is a modify permissions attribute
- (void)addRelativeFilePath:(NSString *)relativeFilePath realFilePath:(nullable NSString *)filePath attributes:(SPUDeltaFileAttributes)attributes permissions:(uint16_t)permissions;

@end

NS_ASSUME_NONNULL_END
