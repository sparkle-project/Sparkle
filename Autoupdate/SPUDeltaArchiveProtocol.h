//
//  SPUDeltaArchiveProtocol.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, SPUDeltaFileAttributes) {
    SPUDeltaFileAttributesDelete = (1u << 0),
    SPUDeltaFileAttributesExtract = (1u << 1),
    SPUDeltaFileAttributesModifyPermissions = (1u << 2),
    SPUDeltaFileAttributesBinaryDiff = (1u << 3),
};

@protocol SPUDeltaArchiveProtocol <NSObject>

- (void)close;

// For reading

@property (nonatomic, readonly, class) BOOL supportsSafeExtraction;

+ (BOOL)getMajorDeltaVersion:(uint16_t *)outMajorDiffVersion minorDeltaVersion:(uint16_t *)outMinorDiffVersion fromPatchFile:(NSString *)patchFile;

- (void)getMajorDeltaVersion:(nullable uint16_t *)outMajorDiffVersion minorDeltaVersion:(nullable uint16_t *)outMinorDiffVersion beforeTreeHash:(NSString * _Nullable __autoreleasing * _Nullable)outBeforeTreeHash afterTreeHash:(NSString * _Nullable __autoreleasing * _Nullable)outAfterTreeHash;

- (BOOL)enumerateItems:(void (^)(const void *item, NSString *relativePath, SPUDeltaFileAttributes attributes, uint16_t permissions, BOOL *stop))itemHandler;

- (BOOL)extractItem:(const void *)item destination:(NSString *)destinationPath;

// For writing

- (void)setMajorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(NSString *)beforeTreeHash afterTreeHash:(NSString *)afterTreeHash;

- (void)addRelativeFilePath:(NSString *)relativeFilePath realFilePath:(nullable NSString *)filePath attributes:(SPUDeltaFileAttributes)attributes permissions:(nullable NSNumber *)permissions;

@end

NS_ASSUME_NONNULL_END
