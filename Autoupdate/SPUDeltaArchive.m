//
//  SPUDeltaArchive.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/29/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUDeltaArchive.h"
#import "SPUDeltaArchiveProtocol.h"
#import "SPUSparkleDeltaArchive.h"
#import "SPUXarDeltaArchive.h"
#import <CommonCrypto/CommonDigest.h>


#include "AppKitPrevention.h"

SPUDeltaCompressionMode SPUDeltaCompressionModeDefault = SPUDeltaCompressionModeBzip2;

id<SPUDeltaArchiveProtocol> _Nullable SPUDeltaArchiveForReading(NSString *patchFile)
{
    id<SPUDeltaArchiveProtocol> sparkleArchive = [[SPUSparkleDeltaArchive alloc] initWithPatchFileForReading:patchFile];
    
    id<SPUDeltaArchiveProtocol> finalArchive;
    if (sparkleArchive != nil) {
        finalArchive = sparkleArchive;
    } else {
        finalArchive = [[SPUXarDeltaArchive alloc] initWithPatchFileForReading:patchFile];
    }
    return finalArchive;
}

@implementation SPUDeltaArchiveItem

@synthesize relativeFilePath = _relativeFilePath;
@synthesize physicalFilePath = _physicalFilePath;
@synthesize commands = _commands;
@synthesize permissions = _permissions;
@synthesize context = _context;
@synthesize originalMode = _originalMode;
@synthesize codedDataLength = _codedDataLength;

- (instancetype)initWithRelativeFilePath:(NSString *)relativeFilePath commands:(SPUDeltaItemCommands)commands permissions:(uint16_t)permissions
{
    self = [super init];
    if (self != nil) {
        _relativeFilePath = [relativeFilePath copy];
        _commands = commands;
        _permissions = permissions;
    }
    return self;
}

@end

@implementation SPUDeltaArchiveHeader
{
    unsigned char _beforeTreeHash[CC_SHA1_DIGEST_LENGTH];
    unsigned char _afterTreeHash[CC_SHA1_DIGEST_LENGTH];
}

@synthesize majorVersion = _majorVersion;
@synthesize minorVersion = _minorVersion;

- (instancetype)initWithMajorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(const unsigned char *)beforeTreeHash afterTreeHash:(const unsigned char *)afterTreeHash
{
    self = [super init];
    if (self != nil)
    {
        _majorVersion = majorVersion;
        _minorVersion = minorVersion;
        
        memcpy(_beforeTreeHash, beforeTreeHash, sizeof(_beforeTreeHash));
        memcpy(_afterTreeHash, afterTreeHash, sizeof(_afterTreeHash));
    }
    return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

- (unsigned char *)beforeTreeHash
{
    return _beforeTreeHash;
}

- (unsigned char *)afterTreeHash
{
    return _afterTreeHash;
}

#pragma clang diagnostic pop

@end
