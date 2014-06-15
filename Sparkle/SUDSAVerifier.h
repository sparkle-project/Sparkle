//
//  SUDSAVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
//  Includes code by Zach Waldowski on 10/18/13.
//  Copyright (c) 2014 Big Nerd Ranch. All rights reserved.
//
//  Includes code from Plop by Mark Hamlin.
//  Copyright (c) 2011 Mark Hamlin. All rights reserved.
//

#ifndef SUDSAVERIFIER_H
#define SUDSAVERIFIER_H

#import <Cocoa/Cocoa.h>

@interface SUDSAVerifier : NSObject

+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString;

- (instancetype)initWithPublicKeyData:(NSData *)data;
- (instancetype)initWithPublicKeyString:(NSString *)string;

- (BOOL)verifyURL:(NSURL *)URL signature:(NSData *)signature;
- (BOOL)verifyFileAtPath:(NSString *)path signature:(NSData *)signature;
- (BOOL)verifyStream:(NSInputStream *)stream signature:(NSData *)signature;

@end

#endif
