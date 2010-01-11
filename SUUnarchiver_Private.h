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
+ (void)registerImplementation:(Class)implementation;
+ (NSArray *)unarchiverImplementations;
+ (BOOL)canUnarchivePath:(NSString *)path;
- (id)initWithPath:(NSString *)path host:(SUHost *)host;;

- (void)notifyDelegateOfExtractedLength:(NSNumber *)length;
- (void)notifyDelegateOfSuccess;
- (void)notifyDelegateOfFailure;
@end

#endif
