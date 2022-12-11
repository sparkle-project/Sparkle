//
//  SPUXarDeltaArchive.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SPUDeltaArchiveProtocol.h"
#import "SPUDeltaCompressionMode.h"

NS_ASSUME_NONNULL_BEGIN

// Legacy container format for binary delta archives
@interface SPUXarDeltaArchive : NSObject <SPUDeltaArchiveProtocol>

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile __attribute__((objc_direct));
- (instancetype)initWithPatchFileForReading:(NSString *)patchFile __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
