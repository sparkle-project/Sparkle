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

id<SPUDeltaArchiveProtocol> SPUDeltaArchiveReadPatchAndHeader(NSString *patchFile, SPUDeltaArchiveHeader * _Nullable __autoreleasing * _Nullable outHeader)
{
    id<SPUDeltaArchiveProtocol> sparkleArchive = [[SPUSparkleDeltaArchive alloc] initWithPatchFileForReading:patchFile];
    
    SPUDeltaArchiveHeader *header = [sparkleArchive readHeader];
    if (header == nil) {
        NSError *archiveError = sparkleArchive.error;
        if (archiveError != nil && [archiveError.domain isEqualToString:SPARKLE_DELTA_ARCHIVE_ERROR_DOMAIN] && archiveError.code == SPARKLE_DELTA_ARCHIVE_ERROR_CODE_BAD_MAGIC) {
            // Retry with XAR archive if the magic value is unexpected
            [sparkleArchive close];
            
            id<SPUDeltaArchiveProtocol> xarArchive = [[SPUXarDeltaArchive alloc] initWithPatchFileForReading:patchFile];
            
            SPUDeltaArchiveHeader *xarHeader = [xarArchive readHeader];
            if (outHeader != NULL) {
                *outHeader = xarHeader;
            }
            return xarArchive;
        } else {
            if (outHeader != NULL) {
                *outHeader = nil;
            }
            return sparkleArchive;
        }
    } else {
        if (outHeader != NULL) {
            *outHeader = header;
        }
        return sparkleArchive;
    }
}

@implementation SPUDeltaArchiveItem

@synthesize relativeFilePath = _relativeFilePath;
@synthesize physicalFilePath = _physicalFilePath;
@synthesize clonedRelativePath = _clonedRelativePath;
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
