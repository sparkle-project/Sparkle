//
//  SUInstallationInputData.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallationInputData.h"

static NSString *SURelaunchPathKey = @"SURelaunchPath";
static NSString *SUProgressToolPathKey = @"SUProgressToolPath";
static NSString *SUProgressToolIconPathKey = @"SUProgressToolIconPath";
static NSString *SUHostBundlePathKey = @"SUHostBundlePath";
static NSString *SUUpdateDirectoryPathKey = @"SUUpdateDirectoryPath";
static NSString *SUDownloadNameKey = @"SUDownloadName";
static NSString *SUDSASignatureKey = @"SUDSASignature";
static NSString *SUDecryptionPasswordKey = @"SUDecryptionPassword";

@implementation SUInstallationInputData

@synthesize relaunchPath = _relaunchPath;
@synthesize progressToolPath = _progressToolPath;
@synthesize progressToolIconPath = _progressToolIconPath;
@synthesize hostBundlePath = _hostBundlePath;
@synthesize updateDirectoryPath = _updateDirectoryPath;
@synthesize downloadName = _downloadName;
@synthesize dsaSignature = _dsaSignature;
@synthesize decryptionPassword = _decryptionPassword;

- (instancetype)initWithRelaunchPath:(NSString *)relaunchPath progressToolPath:(nullable NSString *)progressToolPath progressToolIconPath:(NSString *)progressToolIconPath hostBundlePath:(NSString *)hostBundlePath updateDirectoryPath:(NSString *)updateDirectoryPath downloadName:(NSString *)downloadName dsaSignature:(NSString *)dsaSignature decryptionPassword:(nullable NSString *)decryptionPassword
{
    self = [super init];
    if (self != nil) {
        _relaunchPath = [relaunchPath copy];
        _progressToolPath = [progressToolPath copy];
        _progressToolIconPath = [progressToolIconPath copy];
        _hostBundlePath = [hostBundlePath copy];
        _updateDirectoryPath = [updateDirectoryPath copy];
        _downloadName = [downloadName copy];
        _dsaSignature = [dsaSignature copy];
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
    
    NSString *progressToolPath = [decoder decodeObjectOfClass:[NSString class] forKey:SUProgressToolPathKey];
    
    NSString *progressToolIconPath = [decoder decodeObjectOfClass:[NSString class] forKey:SUProgressToolIconPathKey];
    
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
    
    NSString *dsaSignature = [decoder decodeObjectOfClass:[NSString class] forKey:SUDSASignatureKey];
    if (dsaSignature == nil) {
        return nil;
    }
    
    NSString *decryptionPassword = [decoder decodeObjectOfClass:[NSString class] forKey:SUDecryptionPasswordKey];
    
    return [self initWithRelaunchPath:relaunchPath progressToolPath:progressToolPath progressToolIconPath:progressToolIconPath hostBundlePath:hostBundlePath updateDirectoryPath:updateDirectoryPath downloadName:downloadName dsaSignature:dsaSignature decryptionPassword:decryptionPassword];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.relaunchPath forKey:SURelaunchPathKey];
    if (self.progressToolPath != nil) {
        [coder encodeObject:self.progressToolPath forKey:SUProgressToolPathKey];
    }
    if (self.progressToolIconPath != nil) {
        [coder encodeObject:self.progressToolIconPath forKey:SUProgressToolIconPathKey];
    }
    [coder encodeObject:self.hostBundlePath forKey:SUHostBundlePathKey];
    [coder encodeObject:self.updateDirectoryPath forKey:SUUpdateDirectoryPathKey];
    [coder encodeObject:self.downloadName forKey:SUDownloadNameKey];
    [coder encodeObject:self.dsaSignature forKey:SUDSASignatureKey];
    if (self.decryptionPassword != nil) {
        [coder encodeObject:self.decryptionPassword forKey:SUDecryptionPasswordKey];
    }
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
