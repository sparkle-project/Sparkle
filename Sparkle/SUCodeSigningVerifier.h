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
+ (BOOL)codeSignatureIsValidAtPath:(NSString *)destinationPath error:(NSError **)error;
+ (BOOL)hostApplicationIsCodeSigned;
@end

#endif
