//
//  SUInstallerValidation.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/30/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUHost;

@interface SUInstallerValidation : NSObject

/**
 * If the update is a bundle, then the download must also be signed using DSA.
 * However, a change of DSA public keys is allowed if the Apple Code Signing identities match and are valid.
 * Likewise, a change of Apple Code Signing identities is allowed if the DSA public keys match and the update is valid.
 */
+ (BOOL)validateBundleUpdateForHost:(SUHost *)host newBundlePath:(NSString *)newBundlePath archivePath:(NSString *)archivePath DSASignature:(NSString *)DSASignature;

/*
 * Use this for validating updates by validating the DSA signature using the host's public DSA key
 */
+ (BOOL)validateUpdateForHost:(SUHost *)host archivePath:(NSString *)archivePath DSASignature:(NSString *)DSASignature;

/*
 * Use this for validating a code signature for a bundle.
 * This is simply a consistency check rather than a security one.
 * This will return YES if the code signature is valid on the bundle, or if the bundle is not code signed at all, otherwise returns NO.
 */
+ (BOOL)validateCodeSignatureIfAvailableForBundlePath:(NSString *)bundlePath;

@end
