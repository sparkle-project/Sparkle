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
#import "SPUVerifierInformation.h"


#include "AppKitPrevention.h"

@implementation SUUpdateValidator
{
    SUHost *_host;
    SUSignatures *_signatures;
    NSString *_downloadPath;
    SPUVerifierInformation *_verifierInformation;
    
    BOOL _prevalidatedSignature;
}

- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host verifierInformation:(SPUVerifierInformation * _Nullable)verifierInformation
{
    self = [super init];
    if (self != nil) {
        _downloadPath = [downloadPath copy];
        _signatures = signatures;
        _host = host;
        _verifierInformation = verifierInformation;
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
        if ([SUSignatureVerifier validatePath:_downloadPath withSignatures:signatures withPublicKeys:publicKeys verifierInformation:_verifierInformation error:&innerError]) {
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
            BOOL validationCheckSuccess = [SUSignatureVerifier validatePath:downloadPath withSignatures:signatures withPublicKeys:publicKeys verifierInformation:_verifierInformation error:&innerError];
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
        // We already validated the EdDSA signature
        // Let's check if the update passes Sparkle's basic update policy and that the update is properly signed
        // Currently, this case gets hit only for binary delta updates and .aar/.yaa archives
        
        NSBundle *newBundle = [NSBundle bundleWithURL:installSourceURL];
        SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
        
        SUPublicKeys *publicKeys = host.publicKeys;
        SUPublicKeys *newPublicKeys = newHost.publicKeys;
        
        BOOL oldHasAnyDSAKey = NO;
        BOOL newHasAnyDSAKey = NO;
        BOOL hostIsCodeSigned = NO;
        BOOL updateIsCodeSigned = NO;
        
        [self getHostIsCodeSigned:&hostIsCodeSigned updateIsCodeSigned:&updateIsCodeSigned hostHasAnyDSAKey:&oldHasAnyDSAKey updateHasAnyDSAKey:&newHasAnyDSAKey migratesDSAKeys:NULL hostPublicKeys:publicKeys updatePublicKeys:newPublicKeys hostBundleURL:host.bundle.bundleURL updateBundleURL:installSourceURL];
        
        if (![self passesBasicUpdatePolicyWithHostIsCodeSigned:hostIsCodeSigned updateIsCodeSigned:updateIsCodeSigned hostHasAnyDSAKey:oldHasAnyDSAKey updateHasAnyDSAKey:newHasAnyDSAKey error:error]) {
            return NO;
        }
        
        NSError *innerError = nil;
        if (updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:installSourceURL error:&innerError]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to validate apple code sign signature on bundle after archive validation", NSUnderlyingErrorKey: innerError }];
            }
            
            return NO;
        }
        
        return YES;
    }
}

- (void)getHostIsCodeSigned:(BOOL *)outHostIsCodeSigned updateIsCodeSigned:(BOOL *)outUpdateIsCodeSigned hostHasAnyDSAKey:(BOOL *)outHostHasAnyDSAKey updateHasAnyDSAKey:(BOOL *)outUpdateHasAnyDSAKey migratesDSAKeys:(BOOL *)outMigratesDSAKeys hostPublicKeys:(SUPublicKeys *)hostPublicKeys updatePublicKeys:(SUPublicKeys *)updatePublicKeys hostBundleURL:(NSURL *)hostBundleURL updateBundleURL:(NSURL *)updateBundleURL SPU_OBJC_DIRECT
{
    BOOL oldHasLegacyDSAKey = hostPublicKeys.dsaPubKeyStatus != SUSigningInputStatusAbsent;
    BOOL oldHasEdDSAKey = hostPublicKeys.ed25519PubKeyStatus != SUSigningInputStatusAbsent;
    BOOL oldHasAnyDSAKey = oldHasLegacyDSAKey || oldHasEdDSAKey;
    if (outHostHasAnyDSAKey != NULL) {
        *outHostHasAnyDSAKey = oldHasAnyDSAKey;
    }
    
    BOOL newHasLegacyDSAKey = updatePublicKeys.dsaPubKeyStatus != SUSigningInputStatusAbsent;
    BOOL newHasEdDSAKey = updatePublicKeys.ed25519PubKeyStatus != SUSigningInputStatusAbsent;
    BOOL newHasAnyDSAKey = newHasLegacyDSAKey || newHasEdDSAKey;
    if (outUpdateHasAnyDSAKey != NULL) {
        *outUpdateHasAnyDSAKey = newHasAnyDSAKey;
    }
    
    BOOL migratesDSAKeys = oldHasLegacyDSAKey && !oldHasEdDSAKey && newHasEdDSAKey && !newHasLegacyDSAKey;
    if (outMigratesDSAKeys != NULL) {
        *outMigratesDSAKeys = migratesDSAKeys;
    }
    
    BOOL hostIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:hostBundleURL];
    if (outHostIsCodeSigned != NULL) {
        *outHostIsCodeSigned = hostIsCodeSigned;
    }
    
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtURLIsCodeSigned:updateBundleURL];
    if (outUpdateIsCodeSigned != NULL) {
        *outUpdateIsCodeSigned = updateIsCodeSigned;
    }
}

// This is not essential for security, only a policy
- (BOOL)passesBasicUpdatePolicyWithHostIsCodeSigned:(BOOL)hostIsCodeSigned updateIsCodeSigned:(BOOL)updateIsCodeSigned hostHasAnyDSAKey:(BOOL)hostHasAnyDSAKey updateHasAnyDSAKey:(BOOL)updateHasAnyDSAKey error:(NSError * __autoreleasing *)error SPU_OBJC_DIRECT
{
    // Don't allow removal of (Ed)DSA keys
    if (hostHasAnyDSAKey && !updateHasAnyDSAKey) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"A public (Ed)DSA key was found in the old bundle but no public (Ed)DSA key was found in the new update. Sparkle only supports rotation, but not removal of (Ed)DSA keys. Please add an EdDSA key to the new app." }];
        }
        return NO;
    }
    
    // Don't allow removal of code signing
    if (hostIsCodeSigned && !updateIsCodeSigned) {
        if (error != NULL) {
            if (hostHasAnyDSAKey) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"The old bundle is code signed but the update is not code signed. Sparkle only supports rotation, but not removal of Apple Code Signing identity. Please code sign the new app. If no Apple Code Signing certificate is available, adhoc signing can be used at minimum." }];
            } else {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: @"The old bundle is code signed but the update is not code signed. Please code sign the new app with the same signing identity." }];
            }
        }
        return NO;
    }
    
    return YES;
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
    
    _verifierInformation.actualVersion = newHost.version;
    
    BOOL oldHasAnyDSAKey = NO;
    BOOL newHasAnyDSAKey = NO;
    BOOL migratesDSAKeys = NO;
    BOOL hostIsCodeSigned = NO;
    BOOL updateIsCodeSigned = NO;
    
    [self getHostIsCodeSigned:&hostIsCodeSigned updateIsCodeSigned:&updateIsCodeSigned hostHasAnyDSAKey:&oldHasAnyDSAKey updateHasAnyDSAKey:&newHasAnyDSAKey migratesDSAKeys:&migratesDSAKeys hostPublicKeys:publicKeys updatePublicKeys:newPublicKeys hostBundleURL:host.bundle.bundleURL updateBundleURL:newHost.bundle.bundleURL];
    
    if (![self passesBasicUpdatePolicyWithHostIsCodeSigned:hostIsCodeSigned updateIsCodeSigned:updateIsCodeSigned hostHasAnyDSAKey:oldHasAnyDSAKey updateHasAnyDSAKey:newHasAnyDSAKey error:error]) {
        return NO;
    }

    // Security-critical part starts here
    BOOL passedDSACheck = NO;
    BOOL passedCodeSigning = NO;

    NSError *dsaError = nil;
    if (oldHasAnyDSAKey) {
        // it's critical to check against the old public key, rather than the new key
        passedDSACheck = [SUSignatureVerifier validatePath:downloadedPath withSignatures:signatures withPublicKeys:publicKeys verifierInformation:_verifierInformation error:&dsaError];
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
        if (![SUSignatureVerifier validatePath:downloadedPath withSignatures:signatures withPublicKeys:newPublicKeys verifierInformation:_verifierInformation error:&innerError]) {
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
