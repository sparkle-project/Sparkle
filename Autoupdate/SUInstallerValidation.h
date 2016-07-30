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
 * If the update is a package, then the download must be signed using DSA. No other verification is done.
 *
 * If the update is a bundle, then the download must also be signed using DSA.
 * However, a change of DSA public keys is allowed if the Apple Code Signing identities match and are valid.
 * Likewise, a change of Apple Code Signing identities is allowed if the DSA public keys match and the update is valid.
 *
 */
+ (BOOL)validateUpdateForHost:(SUHost *)host downloadedToPath:(NSString *)downloadedPath extractedToPath:(NSString *)extractedPath DSASignature:(NSString *)DSASignature;

@end
