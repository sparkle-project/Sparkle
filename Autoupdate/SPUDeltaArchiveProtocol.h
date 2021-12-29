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

+ (BOOL)getMajorDeltaVersion:(uint16_t *)outMajorDiffVersion minorDeltaVersion:(uint16_t *)outMinorDiffVersion fromPatchFile:(NSString *)patchFile;

- (void)setMajorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(NSString *)beforeTreeHash afterTreeHash:(NSString *)afterTreeHash;

- (void)addRelativeFilePath:(NSString *)relativeFilePath realFilePath:(nullable NSString *)filePath attributes:(SPUDeltaFileAttributes)attributes permissions:(nullable NSNumber *)permissions;

- (void)close;

@end

NS_ASSUME_NONNULL_END
