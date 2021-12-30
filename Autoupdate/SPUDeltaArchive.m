//
//  SPUDeltaArchive.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/29/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUDeltaArchive.h"
#import "SPUDeltaArchiveProtocol.h"
#import "SPUXarDeltaArchive.h"


#include "AppKitPrevention.h"

id<SPUDeltaArchiveProtocol> _Nullable SPUDeltaArchiveForReading(NSString *patchFile)
{
    return [[SPUXarDeltaArchive alloc] initWithPatchFileForReading:patchFile];
}

id<SPUDeltaArchiveProtocol> _Nullable SPUDeltaArchiveForWriting(NSString *patchFile)
{
    return [[SPUXarDeltaArchive alloc] initWithPatchFileForWriting:patchFile];
}
