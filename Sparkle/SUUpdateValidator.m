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
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUUpdateValidator
{
    SUHost *_host;
    SUSignatures *_signatures;
    NSString *_downloadPath;
    
    BOOL _prevalidatedSignature;
}

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

- (BOOL)validateDownloadPathWithError:(NSError * __autoreleasing *)error
{
    SUPublicKeys *publicKeys = _host.publicKeys;
    SUSignatures *signatures = _signatures;

    if (!publicKeys.hasAnyKeys) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to validate update before unarchiving because no (Ed)DSA public key was found in the old app" }];
        }
    } else {
        NSError *innerError = nil;
        if ([SUSignatureVerifier validatePath:_downloadPath withSignatures:signatures withPublicKeys:publicKeys error:&innerError]) {
            _prevalidatedSignature = YES;
            return YES;
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"(Ed)DSA signature validation before unarchiving failed for update %@", _downloadPath], NSUnderlyingErrorKey: innerError }];
        }
    }
    return NO;
}

- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory error:(NSError * __autoreleasing *)error
{
    SUSignatures *signatures = _signatures;
    NSString *downloadPath = _downloadPath;
    SUHost *host = _host;

#if SPARKLE_BUILD_PACKAGE_SUPPORT
    BOOL isPackage = NO;
#endif

    // install source could point to a new bundle or a package
    NSString *installSource = [SUInstaller installSourcePathInUpdateFolder:updateDirectory forHost:host
#if SPARKLE_BUILD_PACKAGE_SUPPORT
                                                                 isPackage:&isPackage isGuided:NULL
#endif
    ];
    
    if (installSource == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"No suitable install is found in the update. The update will be rejected." }];
        }
        return NO;
    }

    NSURL *installSourceURL = [NSURL fileURLWithPath:installSource];

    if (!_prevalidatedSignature) {
#if SPARKLE_BUILD_PACKAGE_SUPPORT
        // Check to see if we have a package or bundle to validate
        if (isPackage) {
            // If we get here, then the appcast installation type was lying to us.. This error will be caught later when starting the installer.
            // For package type updates, all we do is check if the EdDSA signature is valid
            NSError *innerError = nil;
            SUPublicKeys *publicKeys = host.publicKeys;
            BOOL validationCheckSuccess = [SUSignatureVerifier validatePath:downloadPath withSignatures:signatures withPublicKeys:publicKeys error:&innerError];
            if (!validationCheckSuccess) {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"EdDSA signature validation of the package failed. The update contains an installer package, and valid EdDSA signatures are mandatory for all installer packages. The update will be rejected. Sign the installer with a valid EdDSA key or use an .app bundle update instead.", NSUnderlyingErrorKey: innerError }];
                }
            }
            return validationCheckSuccess;
        } else
#endif
        {
            // For application bundle updates, we check both the EdDSA and Apple code signing signatures
            return [self validateUpdateForHost:host downloadedToPath:downloadPath newBundleURL:installSourceURL signatures:signatures error:error];
        }
    }
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    else if (isPackage) {
        // We already prevalidated the package and nothing else needs to be done
        return YES;
    }
#endif
    else
    {
        // Because we already validated the EdDSA signature, this is just a consistency check to see
        // if the developer signed their application properly with their Apple ID
        // Currently, this case only gets hit for binary delta updates
        
        NSError *innerError = nil;
        if ([SUCodeSigningVerifier bundleAtURLIsCodeSigned:installSourceURL] && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:installSourceURL error:&innerError]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to validate apple code sign signature on bundle after archive validation", NSUnderlyingErrorKey: innerError }];
            }
            
            return NO;
        } else {
            return YES;
        }
    }
}

/**
 * If the update is a bundle, then it must meet any one of:
 *
 *  * old and new Ed(DSA) public keys are the same and valid (it allows change of Code Signing identity), or
 *
 *  * old and new Code Signing identity are the same and valid
 *
 */
- (BOOL)validateUpdateForHost:(SUHost *)host downloadedToPath:(NSString *)downloadedPath newBundleURL:(NSURL *)newBundleURL signatures:(SUSignatures *)signatures error:(NSError * __autoreleasing *)error SPU_OBJC_DIRECT
{
    NSBundle *newBundle = [NSBundle bundleWithURL:newBundleURL];
    if (newBundle == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"No suitable bundle is found in the update. The update will be rejected." }];
        }
        return NO;
    }

    SUPublicKeys *publicKeys = host.publicKeys;

    SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
    SUPublicKeys *newPublicKeys = newHost.publicKeys;
    
    BOOL oldHasLegacyDSAKey = publicKeys.dsaPubKeyStatus != SUSigningInputStatusAbsent;
    BOOL oldHasEdDSAKey = publicKeys.ed25519PubKeyStatus != SUSigningInputStatusAbsent;
    BOOL oldHasAnyDSAKey = oldHasLegacyDSAKey || oldHasEdDSAKey;
    BOOL newHasLegacyDSAKey = newPublicKeys.dsaPubKeyStatus != SUSigningInputStatusAbsent;
    BOOL newHasEdDSAKey = newPublicKeys.ed25519PubKeyStatus != SUSigningInputStatusAbsent;
    BOOL newHasAnyDSAKey = newHasLegacyDSAKey || newHasEdDSAKey;
    BOOL migratesDSAKeys = oldHasLegacyDSAKey && !oldHasEdDSAKey && newHasEdDSAKey && !newHasLegacyDSAKey;
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:newHost.bundle.bundleURL];
    BOOL hostIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:host.bundle.bundleURL];

    // This is not essential for security, only a policy
    if (oldHasAnyDSAKey && !newHasAnyDSAKey) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"A public (Ed)DSA key was found in the old bundle but no public (Ed)DSA key was found in the new update. Sparkle only supports rotation, but not removal of (Ed)DSA keys. Please add an EdDSA key to the new app." }];
        }
        return NO;
    }

    // Security-critical part starts here
    BOOL passedDSACheck = NO;
    BOOL passedCodeSigning = NO;

    NSError *dsaError = nil;
    if (oldHasAnyDSAKey) {
        // it's critical to check against the old public key, rather than the new key
        passedDSACheck = [SUSignatureVerifier validatePath:downloadedPath withSignatures:signatures withPublicKeys:publicKeys error:&dsaError];
    }

    NSError *codeSignedError = nil;
    if (hostIsCodeSigned) {
        passedCodeSigning = [SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:newHost.bundle.bundleURL andMatchesSignatureAtBundleURL:host.bundle.bundleURL error:&codeSignedError];
    }
    // End of security-critical part

    // If the new DSA key differs from the old, then this check is not a security measure, because the new key is not trusted.
    // In that case, the check ensures that the app author has correctly used DSA keys, so that the app will be updateable in the next version.
    if (!passedDSACheck && newHasAnyDSAKey) {
        NSError *innerError = nil;
        if (![SUSignatureVerifier validatePath:downloadedPath withSignatures:signatures withPublicKeys:newPublicKeys error:&innerError]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"The update has a public (Ed)DSA key, but the public key shipped with the update doesn't match the signature. To prevent future problems, the update will be rejected.", NSUnderlyingErrorKey: innerError }];
            }
            return NO;
        }
    }

    // If the new update is code signed but it's not validly code signed, we reject it
    NSError *innerError = nil;
    if (passedDSACheck && updateIsCodeSigned && !passedCodeSigning && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:newHost.bundle.bundleURL error:&innerError]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"The update archive has a valid (Ed)DSA signature, but the app is also signed with Code Signing, which is corrupted. The update will be rejected.", NSUnderlyingErrorKey: innerError }];
        }
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
        
        if (error != NULL) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"The update archive %@, and the %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, acsStatus];
            
            if (dsaError != nil) {
                userInfo[NSUnderlyingErrorKey] = dsaError;
            }
            
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:[userInfo copy]];
        }
    } else {
        if (error != NULL) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"The update archive %@, and the app is signed with a new Code Signing identity that doesn't match code signing of the original app. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus];
            
            if (codeSignedError != nil) {
                userInfo[NSUnderlyingErrorKey] = codeSignedError;
            }
            
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:[userInfo copy]];
        }
    }

    return NO;
}

@end
