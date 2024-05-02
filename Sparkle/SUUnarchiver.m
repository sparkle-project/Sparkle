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
#import "SUFlatPackageUnarchiver.h"


#include "AppKitPrevention.h"

@implementation SUUnarchiver

+ (nullable id <SUUnarchiverProtocol>)unarchiverForPath:(NSString *)path extractionDirectory:(NSString *)extractionDirectory updatingHostBundlePath:(nullable NSString *)hostPath decryptionPassword:(nullable NSString *)decryptionPassword
{
    if ([SUPipedUnarchiver canUnarchivePath:path]) {
        return [[SUPipedUnarchiver alloc] initWithArchivePath:path extractionDirectory:extractionDirectory];
    } else if ([SUDiskImageUnarchiver canUnarchivePath:path]) {
        return [[SUDiskImageUnarchiver alloc] initWithArchivePath:path extractionDirectory:extractionDirectory decryptionPassword:decryptionPassword];
        
    } else if ([SUBinaryDeltaUnarchiver canUnarchivePath:path]) {
        assert(hostPath != nil);
        NSString *nonNullHostPath = hostPath;
        return [[SUBinaryDeltaUnarchiver alloc] initWithArchivePath:path extractionDirectory:extractionDirectory updateHostBundlePath:nonNullHostPath];
        
    } else if ([SUFlatPackageUnarchiver canUnarchivePath:path]) {
        return [[SUFlatPackageUnarchiver alloc] initWithFlatPackagePath:path extractionDirectory:extractionDirectory];
    }
    return nil;
}

@end
