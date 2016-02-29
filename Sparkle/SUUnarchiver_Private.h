//
//  SUUnarchiver_Private.h
//  Sparkle
//
//  Created by Andy Matuschak on 6/17/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUNARCHIVER_PRIVATE_H
#define SUUNARCHIVER_PRIVATE_H

#import <Foundation/Foundation.h>
#import "SUUnarchiver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUnarchiver (Private)
+ (void)registerImplementation:(Class)implementation;
+ (NSArray *)unarchiverImplementations;
+ (BOOL)canUnarchivePath:(NSString *)path;
- (instancetype)initWithPath:(NSString *)archive hostBundlePath:(NSString *)host;

- (void)notifyDelegateOfProgress:(double)progress;
- (void)notifyDelegateOfSuccess;
- (void)notifyDelegateOfFailure;
@end

#endif
