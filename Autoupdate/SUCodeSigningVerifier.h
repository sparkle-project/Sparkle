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

+ (BOOL)codeSignatureAtBundleURL:(NSURL *)oldBundleURL matchesSignatureAtBundleURL:(NSURL *)newBundleURL error:(NSError  **)error;

+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL checkNestedCode:(BOOL)checkNestedCode error:(NSError **)error;

// Same as above except does not check for nested code. This method should be used by the framework.
+ (BOOL)codeSignatureIsValidAtBundleURL:(NSURL *)bundleURL error:(NSError *__autoreleasing *)error;

+ (BOOL)bundleAtURLIsCodeSigned:(NSURL *)bundleURL;
@end

#endif
