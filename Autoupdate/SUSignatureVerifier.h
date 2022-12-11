//
//  SUSignatureVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright 2014 Big Nerd Ranch. Licensed under MIT.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright 2011 Mark Hamlin. Licensed under BSD.
//

#ifndef SUDSAVERIFIER_H
#define SUDSAVERIFIER_H

#import <Foundation/Foundation.h>
@class SUSignatures;
@class SUPublicKeys;

@interface SUSignatureVerifier : NSObject

+ (BOOL)validatePath:(NSString *)path withSignatures:(SUSignatures *)signatures withPublicKeys:(SUPublicKeys *)pkeys error:(NSError * __autoreleasing *)error __attribute__((objc_direct));

- (instancetype)initWithPublicKeys:(SUPublicKeys *)pkeys __attribute__((objc_direct));

- (BOOL)verifyFileAtPath:(NSString *)path signatures:(SUSignatures *)signatures error:(NSError * __autoreleasing *)error __attribute__((objc_direct));

@end

#endif
