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
- (instancetype)initWithPath:(NSString *)archive hostBundlePath:(NSString *)host;

- (void)notifyProgress:(double)progress;
- (void)unarchiverDidFinish;
- (void)unarchiverDidFailWithError:(NSError *)err;
@end

#endif
