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

#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT_MEMBERS
#endif
@interface SUCodeSigningVerifier : NSObject

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)newBundleURL andMatchesSignatureAtBundleURL:(NSURL *)oldBundleURL error:(NSError **)error;

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL checkNestedCode:(BOOL)checkNestedCode error:(NSError **)error;

// Same as above except does not check for nested code. This method should be used by the framework.
+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL error:(NSError *__autoreleasing *)error;

+ (BOOL)bundleAtURLIsCodeSigned:(NSURL *)bundleURL;
@end

#endif
