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
// pass nil as an application path to check a host one
+ (BOOL)codeSignatureAtPath:(NSString *)hostPath matchesSignatureAtPath:(NSString *)otherAppPath error:(NSError **)error;
+ (BOOL)codeSignatureIsValidAtPath:(NSString *)applicationPath error:(NSError **)error;
+ (BOOL)applicationAtPathIsCodeSigned:(NSString *)applicationPath;
+ (BOOL)hostApplicationIsSandboxed;
@end

#endif
