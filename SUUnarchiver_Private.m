//
//  SUUnarchiver_Private.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/17/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUnarchiver_Private.h"

@implementation SUUnarchiver (Private)

- _initWithPath:(NSString *)path
{
	if ((self = [super init]))
		archivePath = [path copy];
	return self;
}

- (void)dealloc
{
	[archivePath release];
	[super dealloc];
}

+ (BOOL)_canUnarchivePath:(NSString *)path
{
	return NO;
}

- (void)_notifyDelegateOfExtractedLength:(long)length
{
	if ([delegate respondsToSelector:@selector(unarchiver:extractedLength:)])
		[delegate unarchiver:self extractedLength:length];
}

- (void)_notifyDelegateOfSuccess
{
	if ([delegate respondsToSelector:@selector(unarchiverDidFinish:)])
		[delegate performSelector:@selector(unarchiverDidFinish:) withObject:self];
}

- (void)_notifyDelegateOfFailure
{
	if ([delegate respondsToSelector:@selector(unarchiverDidFail:)])
		[delegate performSelector:@selector(unarchiverDidFail:) withObject:self];
}

static NSMutableArray *__unarchiverImplementations;

+ (void)_registerImplementation:(Class)implementation
{
	if (!__unarchiverImplementations)
		__unarchiverImplementations = [[NSMutableArray alloc] init];
	[__unarchiverImplementations addObject:implementation];
}

+ (NSArray *)_unarchiverImplementations
{
	return [NSArray arrayWithArray:__unarchiverImplementations];
}

@end
