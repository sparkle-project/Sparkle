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

+ (nullable id <SUUnarchiverProtocol>)unarchiverForPath:(NSString *)path updatingHostBundlePath:(nullable NSString *)hostPath decryptionPassword:(nullable NSString *)decryptionPassword expectingInstallationType:(NSString *)installationType
{
    if ([SUPipedUnarchiver canUnarchivePath:path]) {
        return [[SUPipedUnarchiver alloc] initWithArchivePath:path];
        
    }
#if SPARKLE_BUILD_DMG_SUPPORT
    else if ([SUDiskImageUnarchiver canUnarchivePath:path]) {
        return [[SUDiskImageUnarchiver alloc] initWithArchivePath:path decryptionPassword:decryptionPassword];
        
    }
#endif
    else if ([SUBinaryDeltaUnarchiver canUnarchivePath:path]) {
        assert(hostPath != nil);
        NSString *nonNullHostPath = hostPath;
        return [[SUBinaryDeltaUnarchiver alloc] initWithArchivePath:path updateHostBundlePath:nonNullHostPath];
    }
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    else if ([SUFlatPackageUnarchiver canUnarchivePath:path]) {
        // Flat packages are only supported for guided packaage installs
        return [[SUFlatPackageUnarchiver alloc] initWithFlatPackagePath:path expectingInstallationType:installationType];
    }
#endif
    return nil;
}

@end
