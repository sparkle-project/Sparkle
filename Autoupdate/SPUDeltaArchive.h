//
//  SPUDeltaArchive.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/29/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SPUDeltaArchiveProtocol;

NS_ASSUME_NONNULL_BEGIN

id<SPUDeltaArchiveProtocol> _Nullable SPUDeltaArchiveForReading(NSString *patchFile);
id<SPUDeltaArchiveProtocol> _Nullable SPUDeltaArchiveForWriting(NSString *patchFile);

NS_ASSUME_NONNULL_END
