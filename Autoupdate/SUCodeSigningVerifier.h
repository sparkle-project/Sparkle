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

+ (BOOL)codeSignatureAtBundleURL:(NSURL *)oldBundleURL matchesSignatureAtBundleURL:(NSURL *)newBundleURL error:(NSError  **)error __attribute__((objc_direct));

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL checkNestedCode:(BOOL)checkNestedCode error:(NSError **)error __attribute__((objc_direct));

// Same as above except does not check for nested code. This method should be used by the framework.
+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL error:(NSError *__autoreleasing *)error __attribute__((objc_direct));

+ (BOOL)bundleAtURLIsCodeSigned:(NSURL *)bundleURL __attribute__((objc_direct));
@end

#endif
