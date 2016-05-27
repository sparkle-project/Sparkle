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

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUUnarchiver

+ (nullable id <SUUnarchiverProtocol>)unarchiverForPath:(NSString *)path updatingHostBundlePath:(nullable NSString *)hostPath decryptionPassword:(nullable NSString *)decryptionPassword delegate:(nullable id <SUUnarchiverDelegate>)delegate
{
    if ([SUPipedUnarchiver canUnarchivePath:path]) {
        return [[SUPipedUnarchiver alloc] initWithArchivePath:path delegate:delegate];
        
    } else if ([SUDiskImageUnarchiver canUnarchivePath:path]) {
        return [[SUDiskImageUnarchiver alloc] initWithArchivePath:path decryptionPassword:decryptionPassword delegate:delegate];
        
    } else if ([SUBinaryDeltaUnarchiver canUnarchivePath:path]) {
        assert(hostPath != nil);
        NSString *nonNullHostPath = hostPath;
        return [[SUBinaryDeltaUnarchiver alloc] initWithArchivePath:path updateHostBundlePath:nonNullHostPath delegate:delegate];
        
    }
    return nil;
}

@end
