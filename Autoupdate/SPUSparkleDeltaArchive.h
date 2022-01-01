//
//  SPUSparkleDeltaArchive.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SPUDeltaArchiveProtocol.h"

NS_ASSUME_NONNULL_BEGIN

#define SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN @"Sparkle Delta Archive"
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_MAGIC 1
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_COMPRESSION_VALUE 2
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CHUNK_SIZE 3
#define SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_CLONE_LOOKUP 4

@interface SPUSparkleDeltaArchive : NSObject <SPUDeltaArchiveProtocol>

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile compression:(SPUDeltaCompressionMode)compression compressionLevel:(int32_t)compressionLevel;
- (instancetype)initWithPatchFileForReading:(NSString *)patchFile;

@end

NS_ASSUME_NONNULL_END
