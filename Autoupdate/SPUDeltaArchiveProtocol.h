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

// Note: BinaryDiff cannot coexist together with Delete
typedef NS_ENUM(uint8_t, SPUDeltaFileAttributes) {
    SPUDeltaFileAttributesDelete = (1u << 0),
    SPUDeltaFileAttributesExtract = (1u << 1),
    SPUDeltaFileAttributesModifyPermissions = (1u << 2),
    SPUDeltaFileAttributesBinaryDiff = (1u << 3),
};

// Compression mode to use during patch creation
typedef NS_ENUM(uint8_t, SPUDeltaCompressionMode) {
    SPUDeltaCompressionModeNone = 0,
    SPUDeltaCompressionModeBzip2 = 1
};

#define DEFAULT_COMPRESSION_MODE SPUDeltaCompressionModeBzip2
#define DEFAULT_COMPRESSION_LEVEL_FOR_DEFAULT_COMPRESSION_MODE 9

// Represents header for our archive
@interface SPUDeltaArchiveHeader : NSObject

- (instancetype)initWithMajorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(const unsigned char *)beforeTreeHash afterTreeHash:(const unsigned char *)afterTreeHash;

@property (nonatomic, readonly) uint16_t majorVersion;
@property (nonatomic, readonly) uint16_t minorVersion;
@property (nonatomic, readonly) unsigned char *beforeTreeHash;
@property (nonatomic, readonly) unsigned char *afterTreeHash;

@end

// Represents an item we read or write to in our delta archive
@interface SPUDeltaArchiveItem : NSObject

- (instancetype)initWithRelativeFilePath:(NSString *)relativeFilePath attributes:(SPUDeltaFileAttributes)attributes permissions:(uint16_t)permissions;

@property (nonatomic, readonly) NSString *relativeFilePath;
@property (nonatomic, nullable) NSString *physicalFilePath;
@property (nonatomic, readonly) SPUDeltaFileAttributes attributes;
@property (nonatomic, readonly) uint16_t permissions;
@property (nonatomic, nullable, copy) void (^encodedCompletionHandler)(void);

// Private properties
@property (nonatomic, nullable) const void *context;
@property (nonatomic) uint16_t originalMode;
@property (nonatomic) uint64_t codedDataLength;

@end

// A protocol for reading and writing binary delta patches
@protocol SPUDeltaArchiveProtocol <NSObject>

@property (nonatomic, readonly, class) BOOL maySupportSafeExtraction;

// Closes file for reading/writing, called in -dealloc if it's not called manually
- (void)close;

// For reading

// Retrieves metadata for the archive including major/minor version and expected bundle hashes
- (nullable SPUDeltaArchiveHeader *)readHeader;

// Enumerate through items in the patch file and read the path, attributes, permissions (if permission attribute is available), and way to stop enumeration
- (BOOL)enumerateItems:(void (^)(SPUDeltaArchiveItem *item, BOOL *stop))itemHandler;

// Extract a file item from the patch file to a destination file
// The item's physical file path must be set as a destination
- (BOOL)extractItem:(SPUDeltaArchiveItem *)item;

// For writing

// Set metadata for archive including major/minor version and expected bundle hashes
- (void)writeHeader:(SPUDeltaArchiveHeader *)header;

// Add item to patch file
// Physical file path must be provided if there is an extract or binary delta attribute
// Permissions are used only if there is a modify permissions attribute
- (void)addItem:(SPUDeltaArchiveItem *)item;

- (BOOL)finishEncodingItems;

@end

NS_ASSUME_NONNULL_END
