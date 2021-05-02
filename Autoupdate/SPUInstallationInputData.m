//
//  SPUInstallationInputData.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallationInputData.h"
#import "SPUInstallationType.h"
#import "SUSignatures.h"

#include "AppKitPrevention.h"

static NSString *SURelaunchPathKey = @"SURelaunchPath";
static NSString *SUHostBundlePathKey = @"SUHostBundlePath";
static NSString *SUUpdateDirectoryPathKey = @"SUUpdateDirectoryPath";
static NSString *SUDownloadNameKey = @"SUDownloadName";
static NSString *SUSignaturesKey = @"SUSignatures";
static NSString *SUDecryptionPasswordKey = @"SUDecryptionPassword";
static NSString *SUInstallationTypeKey = @"SUInstallationType";

@implementation SPUInstallationInputData

@synthesize relaunchPath = _relaunchPath;
@synthesize hostBundlePath = _hostBundlePath;
@synthesize updateDirectoryPath = _updateDirectoryPath;
@synthesize downloadName = _downloadName;
@synthesize signatures = _signatures;
@synthesize decryptionPassword = _decryptionPassword;
@synthesize installationType = _installationType;

- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath hostBundlePath:(NSString *)hostBundlePath updateDirectoryPath:(NSString *)updateDirectoryPath downloadName:(NSString *)downloadName installationType:(NSString *)installationType signatures:(SUSignatures * _Nullable)signatures decryptionPassword:(nullable NSString *)decryptionPassword
{
    self = [super init];
    if (self != nil) {
        _relaunchPath = [relaunchPath copy];
        _hostBundlePath = [hostBundlePath copy];
        _updateDirectoryPath = [updateDirectoryPath copy];
        _downloadName = [downloadName copy];
        
        _installationType = [installationType copy];
        assert(SPUValidInstallationType(_installationType));
        
        _signatures = signatures;
        _decryptionPassword = [decryptionPassword copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    NSString *relaunchPath = [decoder decodeObjectOfClass:[NSString class] forKey:SURelaunchPathKey];
    if (relaunchPath == nil) {
        return nil;
    }
    
    NSString *hostBundlePath = [decoder decodeObjectOfClass:[NSString class] forKey:SUHostBundlePathKey];
    if (hostBundlePath == nil) {
        return nil;
    }
    
    NSString *updateDirectoryPath = [decoder decodeObjectOfClass:[NSString class] forKey:SUUpdateDirectoryPathKey];
    if (updateDirectoryPath == nil) {
        return nil;
    }
    
    NSString *downloadName = [decoder decodeObjectOfClass:[NSString class] forKey:SUDownloadNameKey];
    if (downloadName == nil) {
        return nil;
    }
    
    NSString *installationType = [decoder decodeObjectOfClass:[NSString class] forKey:SUInstallationTypeKey];
    if (!SPUValidInstallationType(installationType)) {
        return nil;
    }
    
    SUSignatures *signatures = [decoder decodeObjectOfClass:[SUSignatures class] forKey:SUSignaturesKey];
    if (signatures == nil) {
        return nil;
    }
    
    NSString *decryptionPassword = [decoder decodeObjectOfClass:[NSString class] forKey:SUDecryptionPasswordKey];
    
    return [self initWithRelaunchPath:relaunchPath hostBundlePath:hostBundlePath updateDirectoryPath:updateDirectoryPath downloadName:downloadName installationType:installationType signatures:signatures decryptionPassword:decryptionPassword];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.relaunchPath forKey:SURelaunchPathKey];
    [coder encodeObject:self.hostBundlePath forKey:SUHostBundlePathKey];
    [coder encodeObject:self.updateDirectoryPath forKey:SUUpdateDirectoryPathKey];
    [coder encodeObject:self.installationType forKey:SUInstallationTypeKey];
    [coder encodeObject:self.downloadName forKey:SUDownloadNameKey];
    [coder encodeObject:self.signatures forKey:SUSignaturesKey];
    if (self.decryptionPassword != nil) {
        [coder encodeObject:self.decryptionPassword forKey:SUDecryptionPasswordKey];
    }
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
