//
//  SPUXarDeltaArchive.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SPUDeltaArchiveProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// Legacy container format for binary delta archives
@interface SPUXarDeltaArchive : NSObject <SPUDeltaArchiveProtocol>

- (nullable instancetype)initWithPatchFileForWriting:(NSString *)patchFile compression:(SPUDeltaCompressionMode)compression compressionLevel:(int32_t)compressionLevel;
- (nullable instancetype)initWithPatchFileForReading:(NSString *)patchFile;

@end

NS_ASSUME_NONNULL_END
