//
//  SUUnarchiver_Private.h
//  Sparkle
//
//  Created by Andy Matuschak on 6/17/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUNARCHIVER_PRIVATE_H
#define SUUNARCHIVER_PRIVATE_H

#import <Cocoa/Cocoa.h>
#import "SUUnarchiver.h"

@interface SUUnarchiver (Private)
+ (void)_registerImplementation:(Class)implementation;
+ (NSArray *)_unarchiverImplementations;
+ (BOOL)_canUnarchivePath:(NSString *)path;
- _initWithPath:(NSString *)path;

- (void)_notifyDelegateOfExtractedLength:(long)length;
- (void)_notifyDelegateOfSuccess;
- (void)_notifyDelegateOfFailure;
@end

#endif
