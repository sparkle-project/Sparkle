//
//  SUUpdateValidator.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdateValidator.h"
#import "SPUInstallerValidation.h"
#import "SUInstaller.h"
#import "SUHost.h"
#import "SULog.h"

#ifdef _APPKITDEFINES_H
#error This is a "daemon-safe" class and should NOT import AppKit
#endif

@interface SUUpdateValidator ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) BOOL prevalidatedDsaSignature;
@property (nonatomic, readonly) NSString *dsaSignature;
@property (nonatomic, readonly) NSString *downloadPath;

@end

@implementation SUUpdateValidator

@synthesize host = _host;
@synthesize canValidate = _canValidate;
@synthesize prevalidatedDsaSignature = _prevalidatedDsaSignature;
@synthesize dsaSignature = _dsaSignature;
@synthesize downloadPath = _downloadPath;

- (instancetype)initWithDownloadPath:(NSString *)downloadPath dsaSignature:(NSString *)dsaSignature host:(SUHost *)host performingPrevalidation:(BOOL)performingPrevalidation
{
    self = [super init];
    if (self != nil) {
        BOOL canValidate;
        BOOL prevalidatedDsaSignature;
        if (performingPrevalidation) {
            NSString *publicDSAKey = host.publicDSAKey;

            if (publicDSAKey == nil) {
                prevalidatedDsaSignature = NO;
                SULog(@"Failed to validate update before unarchiving because no DSA key was found");
            } else if (dsaSignature == nil) {
                prevalidatedDsaSignature = NO;
                SULog(@"Failed to validate update before unarchiving because no DSA signature was found");
            } else {
                prevalidatedDsaSignature = [SPUInstallerValidation validateUpdateForHost:host archivePath:downloadPath DSASignature:dsaSignature];
                if (!prevalidatedDsaSignature) {
                    SULog(@"DSA signature validation before unarchiving failed for update %@", downloadPath);
                }
            }

            canValidate = prevalidatedDsaSignature;
        } else {
            prevalidatedDsaSignature = NO;
            canValidate = YES;
        }

        _canValidate = canValidate;
        _prevalidatedDsaSignature = prevalidatedDsaSignature;
        _downloadPath = [downloadPath copy];
        _dsaSignature = [dsaSignature copy];
        _host = host;
    }
    return self;
}

- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory
{
    assert(self.canValidate);

    NSString *DSASignature = self.dsaSignature;
    NSString *downloadPath = self.downloadPath;
    SUHost *host = self.host;

    BOOL prevalidatedDsaSignature = self.prevalidatedDsaSignature;

    BOOL isPackage = NO;

    // install source could point to a new bundle or a package
    NSString *installSource = [SUInstaller installSourcePathInUpdateFolder:updateDirectory forHost:host isPackage:&isPackage isGuided:NULL];
    if (installSource == nil) {
        SULog(@"No suitable install is found in the update. The update will be rejected.");
        return NO;
    }

    NSURL *installSourceURL = [NSURL fileURLWithPath:installSource];

    if (!prevalidatedDsaSignature) {
        // Check to see if we have a package or bundle to validate
        if (isPackage) {
            // If we get here, then the appcast installation type was lying to us.. This error will be caught later when starting the installer.
            // For package type updates, all we do is check if the DSA signature is valid
            BOOL validationCheckSuccess = [SPUInstallerValidation validateUpdateForHost:host archivePath:downloadPath DSASignature:DSASignature];
            if (!validationCheckSuccess) {
                SULog(@"DSA signature validation of the package failed. The update contains an installer package, and valid DSA signatures are mandatory for all installer packages. The update will be rejected. Sign the installer with a valid DSA key or use an .app bundle update instead.");
            }
            return validationCheckSuccess;
        } else {
            // For application bundle updates, we check both the DSA and Apple code signing signatures
            return [SPUInstallerValidation validateBundleUpdateForHost:host newBundleURL:installSourceURL archivePath:downloadPath DSASignature:DSASignature];
        }
    } else if (isPackage) {
        // We shouldn't get here because we don't validate packages before extracting them currently
        SULog(@"Error: not expecting to find package after being required to validate update before extraction");
        return NO;
    } else {
        // Because we already validated the DSA signature, this is just a consistency check to see
        // if the developer signed their application properly with their Apple ID
        // Currently, this case only gets hit for binary delta updates
        return [SPUInstallerValidation validateCodeSignatureIfAvailableForBundleURL:installSourceURL];
    }
}

@end
