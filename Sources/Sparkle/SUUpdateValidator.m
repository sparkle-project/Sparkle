//
//  SUUpdateValidator.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdateValidator.h"
#import "SUSignatureVerifier.h"
#import "SUCodeSigningVerifier.h"
#import "SUInstaller.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUSignatures.h"

#include "AppKitPrevention.h"

@interface SUUpdateValidator ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic) BOOL prevalidatedSignature;
@property (nonatomic) BOOL downloadPrevalidationFailed;
@property (strong, nonatomic, readonly) SUSignatures *signatures;
@property (nonatomic, readonly) NSString *downloadPath;

@end

@implementation SUUpdateValidator

@synthesize host = _host;
@synthesize prevalidatedSignature = _prevalidatedSignature;
@synthesize signatures = _signatures;
@synthesize downloadPrevalidationFailed = _downloadPrevalidationFailed;
@synthesize downloadPath = _downloadPath;

- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host
{
    self = [super init];
    if (self != nil) {
        _downloadPath = [downloadPath copy];
        _signatures = signatures;
        _host = host;
    }
    return self;
}

- (BOOL)validateDownloadPath {
    SUPublicKeys *publicKeys = self.host.publicKeys;
    SUSignatures *signatures = self.signatures;

    if (publicKeys.dsaPubKey == nil && publicKeys.ed25519PubKey == nil) {
        SULog(SULogLevelError, @"Failed to validate update before unarchiving because no (Ed)DSA public key was found in the old app");
    } else {
        if ([SUSignatureVerifier validatePath:self.downloadPath withSignatures:signatures withPublicKeys:publicKeys]) {
            self.prevalidatedSignature = YES;
            return YES;
        }
        SULog(SULogLevelError, @"(Ed)DSA signature validation before unarchiving failed for update %@", self.downloadPath);
    }
    self.downloadPrevalidationFailed = YES;
    return NO;
}

- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory
{
    if (self.downloadPrevalidationFailed) {
        return NO;
    }

    SUSignatures *signatures = self.signatures;
    SUPublicKeys *publicKeys = self.host.publicKeys;
    NSString *downloadPath = self.downloadPath;
    SUHost *host = self.host;

    BOOL isPackage = NO;

    // install source could point to a new bundle or a package
    NSString *installSource = [SUInstaller installSourcePathInUpdateFolder:updateDirectory forHost:host isPackage:&isPackage isGuided:NULL];
    if (installSource == nil) {
        SULog(SULogLevelError, @"No suitable install is found in the update. The update will be rejected.");
        return NO;
    }

    NSURL *installSourceURL = [NSURL fileURLWithPath:installSource];

    if (!self.prevalidatedSignature) {
        // Check to see if we have a package or bundle to validate
        if (isPackage) {
            // For package type updates, all we do is check if the DSA signature is valid
            BOOL validationCheckSuccess = [SUSignatureVerifier validatePath:downloadPath withSignatures:signatures withPublicKeys:publicKeys];
            if (!validationCheckSuccess) {
                SULog(SULogLevelError, @"DSA signature validation of the package failed. The update contains an installer package, and valid DSA signatures are mandatory for all installer packages. The update will be rejected. Sign the installer with a valid DSA key or use an .app bundle update instead.");
            }
            return validationCheckSuccess;
        } else {
            // For application bundle updates, we check both the DSA and Apple code signing signatures
            return [self validateUpdateForHost:host downloadedToPath:downloadPath newBundleURL:installSourceURL signatures:signatures];
        }
    } else if (isPackage) {
        // We shouldn't get here because we don't validate packages before extracting them currently
        SULog(SULogLevelError, @"Error: not expecting to find package after being required to validate update before extraction");
        return NO;
    } else {
        // Because we already validated the DSA signature, this is just a consistency check to see
        // if the developer signed their application properly with their Apple ID
        // Currently, this case only gets hit for binary delta updates
        NSError *error = nil;
        if ([SUCodeSigningVerifier bundleAtURLIsCodeSigned:installSourceURL] && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:installSourceURL error:&error]) {
            SULog(SULogLevelError, @"Failed to validate apple code sign signature on bundle after archive validation with error: %@", error);
            return NO;
        } else {
            return YES;
        }
    }
}

/**
 * If the update is a bundle, then it must meet any one of:
 *
 *  * old and new DSA public keys are the same and valid (it allows change of Code Signing identity), or
 *
 *  * old and new Code Signing identity are the same and valid
 *
 */
- (BOOL)validateUpdateForHost:(SUHost *)host downloadedToPath:(NSString *)downloadedPath newBundleURL:(NSURL *)newBundleURL signatures:(SUSignatures *)signatures
{
    NSBundle *newBundle = [NSBundle bundleWithURL:newBundleURL];
    if (newBundle == nil) {
        SULog(SULogLevelError, @"No suitable bundle is found in the update. The update will be rejected.");
        return NO;
    }

    SUPublicKeys *publicKeys = host.publicKeys;

    SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
    SUPublicKeys *newPublicKeys = newHost.publicKeys;
    BOOL oldHasLegacyDSAKey = publicKeys.dsaPubKey != nil;
    BOOL oldHasEdDSAKey = publicKeys.ed25519PubKey != nil;
    BOOL oldHasAnyDSAKey = oldHasLegacyDSAKey || oldHasEdDSAKey;
    BOOL newHasLegacyDSAKey = newPublicKeys.dsaPubKey != nil;
    BOOL newHasEdDSAKey = newPublicKeys.ed25519PubKey != nil;
    BOOL newHasAnyDSAKey = newHasLegacyDSAKey || newHasEdDSAKey;
    BOOL migratesDSAKeys = oldHasLegacyDSAKey && !oldHasEdDSAKey && newHasEdDSAKey && !newHasLegacyDSAKey;
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:newHost.bundle.bundleURL];
    BOOL hostIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:host.bundle.bundleURL];

    // This is not essential for security, only a policy
    if (oldHasAnyDSAKey && !newHasAnyDSAKey) {
        SULog(SULogLevelError, @"A public (Ed)DSA key was found in the old bundle but no public (Ed)DSA key was found in the new update. Sparkle only supports rotation, but not removal of (Ed)DSA keys. Please add an EdDSA key to the new app.");
        return NO;
    }

    // Security-critical part starts here
    BOOL passedDSACheck = NO;
    BOOL passedCodeSigning = NO;

    if (oldHasAnyDSAKey) {
        // it's critical to check against the old public key, rather than the new key
        passedDSACheck = [SUSignatureVerifier validatePath:downloadedPath withSignatures:signatures withPublicKeys:publicKeys];
    }

    if (hostIsCodeSigned) {
        NSError *error = nil;
        passedCodeSigning = [SUCodeSigningVerifier codeSignatureAtBundleURL:host.bundle.bundleURL matchesSignatureAtBundleURL:newHost.bundle.bundleURL error:&error];
    }
    // End of security-critical part

    // If the new DSA key differs from the old, then this check is not a security measure, because the new key is not trusted.
    // In that case, the check ensures that the app author has correctly used DSA keys, so that the app will be updateable in the next version.
    if (!passedDSACheck && newHasAnyDSAKey) {
        if (![SUSignatureVerifier validatePath:downloadedPath withSignatures:signatures withPublicKeys:newPublicKeys]) {
            SULog(SULogLevelError, @"The update has a public (Ed)DSA key, but the public key shipped with the update doesn't match the signature. To prevent future problems, the update will be rejected.");
            return NO;
        }
    }

    NSError *error = nil;
    if (passedDSACheck && updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:newHost.bundle.bundleURL error:&error]) {
        SULog(SULogLevelError, @"The update archive has a valid (Ed)DSA signature, but the app is also signed with Code Signing, which is corrupted: %@. The update will be rejected.", error);
        return NO;
    }

    // Either DSA must be valid, or Apple Code Signing must be valid.
    // We allow failure of one of them, because this allows key rotation without breaking chain of trust.
    if (passedDSACheck || passedCodeSigning) {
        return YES;
    }

    // Now this just explains the failure

    NSString *dsaStatus;
    if (migratesDSAKeys) {
        dsaStatus = @"migrates to new EdDSA keys without keeping the old DSA key for transition";
    } else if (newHasAnyDSAKey) {
        dsaStatus = @"has a new (Ed)DSA key that doesn't match the previous one";
    } else if (oldHasAnyDSAKey) {
        dsaStatus = @"removes the (Ed)DSA key";
    } else {
        dsaStatus = @"isn't signed with an EdDSA key";
    }

    if (!hostIsCodeSigned || !updateIsCodeSigned) {
        NSString *acsStatus = !hostIsCodeSigned ? @"old app hasn't been signed with app Code Signing" : @"new app isn't signed with app Code Signing";
        SULog(SULogLevelError, @"The update archive %@, and the %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, acsStatus);
    } else {
        SULog(SULogLevelError, @"The update archive %@, and the app is signed with a new Code Signing identity that doesn't match code signing of the original app: %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, error);
    }

    return NO;
}

@end
