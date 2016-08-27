//
//  SUCodeSigningVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#ifndef SUCODESIGNINGVERIFIER_H
#define SUCODESIGNINGVERIFIER_H

#import <Foundation/Foundation.h>

@interface SUCodeSigningVerifier : NSObject
+ (BOOL)codeSignatureAtPath:(NSString *)oldBundlePath matchesSignatureAtPath:(NSString *)newBundlePath error:(NSError  **)error;
+ (BOOL)codeSignatureIsValidAtPath:(NSString *)bundlePath error:(NSError **)error;
+ (BOOL)bundleAtPathIsCodeSigned:(NSString *)bundlePath;
@end

#endif
