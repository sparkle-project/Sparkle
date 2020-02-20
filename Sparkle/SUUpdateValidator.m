//
//  SUUpdateValidator.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdateValidator.h"
#import "SUDSAVerifier.h"
#import "SUCodeSigningVerifier.h"
#import "SUInstaller.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUSignatures.h"


#include "AppKitPrevention.h"

@interface SUUpdateValidator ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) BOOL prevalidatedDsaSignature;
@property (nonatomic, readonly) SUSignatures *signatures;
@property (nonatomic, readonly) NSString *downloadPath;

@end

@implementation SUUpdateValidator

@synthesize host = _host;
@synthesize canValidate = _canValidate;
@synthesize prevalidatedDsaSignature = _prevalidatedDsaSignature;
@synthesize signatures = _signatures;
@synthesize downloadPath = _downloadPath;

- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host performingPrevalidation:(BOOL)performingPrevalidation
{
    self = [super init];
    if (self != nil) {
        BOOL canValidate;
        BOOL prevalidatedDsaSignature;
        if (performingPrevalidation) {
            NSString *publicDSAKey = host.publicDSAKey;
            NSData *dsaSignature = signatures.dsaSignature;

            if (publicDSAKey == nil) {
                prevalidatedDsaSignature = NO;
                SULog(SULogLevelError, @"Failed to validate update before unarchiving because no DSA key was found");
            } else if (dsaSignature == nil) {
                prevalidatedDsaSignature = NO;
                SULog(SULogLevelError, @"Failed to validate update before unarchiving because no DSA signature was found");
            } else {
                prevalidatedDsaSignature = [SUDSAVerifier validatePath:downloadPath withDSASignature:dsaSignature withPublicDSAKey:host.publicDSAKey];
                if (!prevalidatedDsaSignature) {
                    SULog(SULogLevelError, @"DSA signature validation before unarchiving failed for update %@", downloadPath);
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
        _signatures = signatures;
        _host = host;
    }
    return self;
}

- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory
{
    assert(self.canValidate);

    NSData *DSASignature = self.signatures.dsaSignature;
    NSString *downloadPath = self.downloadPath;
    SUHost *host = self.host;

    BOOL prevalidatedDsaSignature = self.prevalidatedDsaSignature;

    BOOL isPackage = NO;

    // install source could point to a new bundle or a package
    NSString *installSource = [SUInstaller installSourcePathInUpdateFolder:updateDirectory forHost:host isPackage:&isPackage isGuided:NULL];
    if (installSource == nil) {
        SULog(SULogLevelError, @"No suitable install is found in the update. The update will be rejected.");
        return NO;
    }

    NSURL *installSourceURL = [NSURL fileURLWithPath:installSource];

    if (!prevalidatedDsaSignature) {
        // Check to see if we have a package or bundle to validate
        if (isPackage) {
            // If we get here, then the appcast installation type was lying to us.. This error will be caught later when starting the installer.
            // For package type updates, all we do is check if the DSA signature is valid
            BOOL validationCheckSuccess = [SUDSAVerifier validatePath:downloadPath withDSASignature:DSASignature withPublicDSAKey:host.publicDSAKey];
            if (!validationCheckSuccess) {
                SULog(SULogLevelError, @"DSA signature validation of the package failed. The update contains an installer package, and valid DSA signatures are mandatory for all installer packages. The update will be rejected. Sign the installer with a valid DSA key or use an .app bundle update instead.");
            }
            return validationCheckSuccess;
        } else {
            // For application bundle updates, we check both the DSA and Apple code signing signatures
            return [self validateBundleUpdateForHost:host newBundleURL:installSourceURL archivePath:downloadPath DSASignature:DSASignature];
        }
    } else if (isPackage) {
        // We already prevalidated the package and nothing else needs to be done
        return YES;
    } else {
        // Because we already validated the DSA signature, this is just a consistency check to see
        // if the developer signed their application properly with their Apple ID
        // Currently, this case only gets hit for binary delta updates
        NSError *error = nil;
        if ([SUCodeSigningVerifier bundleAtURLIsCodeSigned:installSourceURL] && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:installSourceURL error:&error]) {
            SULog(SULogLevelError, @"Failed to validate apple code sign signature on bundle after archive validation with error: %@", error);
            return NO;
        }
        return YES;
    }
}

- (BOOL)validateBundleUpdateForHost:(SUHost *)host newBundleURL:(NSURL *)newBundleURL archivePath:(NSString *)archivePath DSASignature:(NSData *)DSASignature
{
    NSBundle *newBundle = [NSBundle bundleWithURL:newBundleURL];
    if (newBundle == nil) {
        SULog(SULogLevelError, @"No suitable bundle is found in the update. The update will be rejected.");
        return NO;
    }
    
    SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
    NSString *newPublicDSAKey = newHost.publicDSAKey;
    
    NSString *publicDSAKey = host.publicDSAKey;
    
    // Downgrade in DSA security should not be possible
    if (publicDSAKey != nil && newPublicDSAKey == nil) {
        SULog(SULogLevelError, @"A public DSA key is found in the old bundle but no public DSA key is found in the new update. For security reasons, the update will be rejected.");
        return NO;
    }
    
    BOOL dsaKeysMatch = (publicDSAKey == nil || newPublicDSAKey == nil) ? NO : [publicDSAKey isEqualToString:newPublicDSAKey];
    
    // If the new DSA key differs from the old, then this check is not a security measure, because the new key is not trusted.
    // In that case, the check ensures that the app author has correctly used DSA keys, so that the app will be updateable in the next version.
    // However if the new and old DSA keys are the same, then this is a security measure.
    if (newPublicDSAKey != nil) {
        if (![SUDSAVerifier validatePath:archivePath withDSASignature:DSASignature withPublicDSAKey:newPublicDSAKey]) {
            SULog(SULogLevelError, @"DSA signature validation failed. The update has a public DSA key and is signed with a DSA key, but the %@ doesn't match the signature. The update will be rejected.",
                  dsaKeysMatch ? @"public key" : @"new public key shipped with the update");
            return NO;
        }
    }
    
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:newBundleURL];
    
    if (dsaKeysMatch) {
        NSError *error = nil;
        if (updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:newBundleURL error:&error]) {
            SULog(SULogLevelError, @"The update archive has a valid DSA signature, but the app is also signed with Code Signing, which is corrupted: %@. The update will be rejected.", error);
            return NO;
        }
    } else {
        NSURL *hostBundleURL = host.bundle.bundleURL;
        BOOL hostIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:hostBundleURL];
        
        NSString *dsaStatus = newPublicDSAKey ? @"has a new DSA key that doesn't match the previous one" : (publicDSAKey ? @"removes the DSA key" : @"isn't signed with a DSA key");
        if (!hostIsCodeSigned || !updateIsCodeSigned) {
            NSString *acsStatus = !hostIsCodeSigned ? @"old app hasn't been signed with app Code Signing" : @"new app isn't signed with app Code Signing";
            SULog(SULogLevelError, @"The update archive %@, and the %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, acsStatus);
            return NO;
        }
        
        NSError *error = nil;
        if (![SUCodeSigningVerifier codeSignatureAtBundleURL:hostBundleURL matchesSignatureAtBundleURL:newBundleURL error:&error]) {
            SULog(SULogLevelError, @"The update archive %@, and the app is signed with a new Code Signing identity that doesn't match code signing of the original app: %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, error);
            return NO;
        }
    }
    
    return YES;
}

@end
