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

@interface SPUSparkleDeltaArchive : NSObject <SPUDeltaArchiveProtocol>

- (nullable instancetype)initWithPatchFileForWriting:(NSString *)patchFile;
- (nullable instancetype)initWithPatchFileForReading:(NSString *)patchFile;

@end

NS_ASSUME_NONNULL_END
