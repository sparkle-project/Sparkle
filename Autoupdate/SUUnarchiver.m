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

+ (BOOL)requiresExtractionMountDirectory:(NSString *)path
{
    if (![SUDiskImageUnarchiver canUnarchivePath:path]) {
        return NO;
    }

    // By providing a directory for mounting, this lets the disk image unarchiver use diskutil over hdiutil
    // diskutil extraction works well across all dmgs only on macOS 27+
    if (@available(macOS 27, *)) {
        return YES;
    } else {
        return NO;
    }
}

+ (nullable id <SUUnarchiverProtocol>)unarchiverForPath:(NSString *)path extractionDirectory:(NSString *)extractionDirectory extractionMountDirectory:(nullable NSString *)extractionMountDirectory updatingHostBundlePath:(nullable NSString *)hostPath decryptionPassword:(nullable NSString *)decryptionPassword expectingInstallationType:(NSString *)installationType
{
    if ([SUPipedUnarchiver canUnarchivePath:path]) {
        return [[SUPipedUnarchiver alloc] initWithArchivePath:path extractionDirectory:extractionDirectory];
    }
    else if ([SUDiskImageUnarchiver canUnarchivePath:path]) {
        return [[SUDiskImageUnarchiver alloc] initWithArchivePath:path extractionDirectory:extractionDirectory extractionMountDirectory:extractionMountDirectory decryptionPassword:decryptionPassword];
    }
    else if ([SUBinaryDeltaUnarchiver canUnarchivePath:path]) {
        assert(hostPath != nil);
        NSString *nonNullHostPath = hostPath;
        return [[SUBinaryDeltaUnarchiver alloc] initWithArchivePath:path extractionDirectory:extractionDirectory updateHostBundlePath:nonNullHostPath];
    }
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    else if ([SUFlatPackageUnarchiver canUnarchivePath:path]) {
        // Flat packages are only supported for guided packaage installs
        return [[SUFlatPackageUnarchiver alloc] initWithFlatPackagePath:path extractionDirectory:extractionDirectory expectingInstallationType:installationType];
    }
#endif
    return nil;
}

@end
