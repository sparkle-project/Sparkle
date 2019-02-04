//
//  SUUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUnarchiver.h"
#import "SUUnarchiverProtocol.h"
#import "SUPipedUnarchiver.h"
#import "SUDiskImageUnarchiver.h"
#import "SUBinaryDeltaUnarchiver.h"
#import "SUPKGUnarchiver.h"

#include "AppKitPrevention.h"

@implementation SUUnarchiver

+ (nullable id <SUUnarchiverProtocol>)unarchiverForPath:(NSString *)path updatingHostBundlePath:(nullable NSString *)hostPath decryptionPassword:(nullable NSString *)decryptionPassword
{
    if ([SUPipedUnarchiver canUnarchivePath:path]) {
        return [[SUPipedUnarchiver alloc] initWithArchivePath:path];
        
    } else if ([SUDiskImageUnarchiver canUnarchivePath:path]) {
        return [[SUDiskImageUnarchiver alloc] initWithArchivePath:path decryptionPassword:decryptionPassword];
        
    } else if ([SUBinaryDeltaUnarchiver canUnarchivePath:path]) {
        assert(hostPath != nil);
        NSString *nonNullHostPath = hostPath;
        return [[SUBinaryDeltaUnarchiver alloc] initWithArchivePath:path updateHostBundlePath:nonNullHostPath];

    } else if ([SUPKGUnarchiver canUnarchivePath:path]) {
        return [[SUPKGUnarchiver alloc] initWithArchivePath:path];
    }
    return nil;
}

@end
