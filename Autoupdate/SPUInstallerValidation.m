//
//  SPUInstallerValidation.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/30/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallerValidation.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUDSAVerifier.h"
#import "SUCodeSigningVerifier.h"

@implementation SPUInstallerValidation

+ (BOOL)validateBundleUpdateForHost:(SUHost *)host newBundlePath:(NSString *)newBundlePath archivePath:(NSString *)archivePath DSASignature:(NSString *)DSASignature
{
    NSBundle *newBundle = [NSBundle bundleWithPath:newBundlePath];
    if (newBundle == nil) {
        SULog(@"No suitable bundle is found in the update. The update will be rejected.");
        return NO;
    }
    
    SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
    NSString *newPublicDSAKey = newHost.publicDSAKey;
    
    NSString *publicDSAKey = host.publicDSAKey;
    
    // Downgrade in DSA security should not be possible
    if (publicDSAKey != nil && newPublicDSAKey == nil) {
        SULog(@"A public DSA key is found in the old bundle but no public DSA key is found in the new update. For security reasons, the update will be rejected.");
        return NO;
    }
    
    BOOL dsaKeysMatch = (publicDSAKey == nil || newPublicDSAKey == nil) ? NO : [publicDSAKey isEqualToString:newPublicDSAKey];
    
    // If the new DSA key differs from the old, then this check is not a security measure, because the new key is not trusted.
    // In that case, the check ensures that the app author has correctly used DSA keys, so that the app will be updateable in the next version.
    // However if the new and old DSA keys are the same, then this is a security measure.
    if (newPublicDSAKey != nil) {
        if (![SUDSAVerifier validatePath:archivePath withEncodedDSASignature:DSASignature withPublicDSAKey:newPublicDSAKey]) {
            SULog(@"DSA signature validation failed. The update has a public DSA key and is signed with a DSA key, but the %@ doesn't match the signature. The update will be rejected.",
                  dsaKeysMatch ? @"public key" : @"new public key shipped with the update");
            return NO;
        }
    }
    
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtPathIsCodeSigned:newBundlePath];
    
    if (dsaKeysMatch) {
        NSError *error = nil;
        if (updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtPath:newBundlePath error:&error]) {
            SULog(@"The update archive has a valid DSA signature, but the app is also signed with Code Signing, which is corrupted: %@. The update will be rejected.", error);
            return NO;
        }
    } else {
        NSString *hostBundlePath = host.bundlePath;
        BOOL hostIsCodeSigned = [SUCodeSigningVerifier bundleAtPathIsCodeSigned:hostBundlePath];
        
        NSString *dsaStatus = newPublicDSAKey ? @"has a new DSA key that doesn't match the previous one" : (publicDSAKey ? @"removes the DSA key" : @"isn't signed with a DSA key");
        if (!hostIsCodeSigned || !updateIsCodeSigned) {
            NSString *acsStatus = !hostIsCodeSigned ? @"old app hasn't been signed with app Code Signing" : @"new app isn't signed with app Code Signing";
            SULog(@"The update archive %@, and the %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, acsStatus);
            return NO;
        }
        
        NSError *error = nil;
        if (![SUCodeSigningVerifier codeSignatureAtPath:hostBundlePath matchesSignatureAtPath:newBundlePath error:&error]) {
            SULog(@"The update archive %@, and the app is signed with a new Code Signing identity that doesn't match code signing of the original app: %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, error);
            return NO;
        }
    }
    
    return YES;
}

+ (BOOL)validateUpdateForHost:(SUHost *)host archivePath:(NSString *)archivePath DSASignature:(NSString *)DSASignature
{
    NSString *publicDSAKey = host.publicDSAKey;
    if (publicDSAKey ==nil){
        SULog(@"Failed to validate delta update because no DSA key was found");
        return NO;
    }
    
    if (DSASignature == nil) {
        SULog(@"Failed to validate delta update because no DSA signature was found");
        return NO;
    }
    
    if (![SUDSAVerifier validatePath:archivePath withEncodedDSASignature:DSASignature withPublicDSAKey:publicDSAKey]) {
        SULog(@"DSA signature validation failed for delta update. This update will be skipped.");
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateCodeSignatureIfAvailableForBundlePath:(NSString *)bundlePath
{
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtPathIsCodeSigned:bundlePath];
    
    NSError *error = nil;
    if (updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtPath:bundlePath error:&error]) {
        SULog(@"Failed to validate code sign signature on bundle at %@", bundlePath);
        return NO;
    }
    return YES;
}

@end
