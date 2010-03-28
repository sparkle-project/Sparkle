//
//  SUUnarchiver_Private.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/17/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUnarchiver_Private.h"

@implementation SUUnarchiver (Private)

- (id)initWithPath:(NSString *)path host:(SUHost *)host
{
	if ((self = [super init]))
	{
		archivePath = [path copy];
		updateHost = [host retain];
	}
	return self;
}

- (void)dealloc
{
	[archivePath release];
	[updateHost release];
	[super dealloc];
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
	return NO;
}

- (void)notifyDelegateOfExtractedLength:(NSNumber *)length
{
	if ([delegate respondsToSelector:@selector(unarchiver:extractedLength:)])
		[delegate unarchiver:self extractedLength:[length unsignedLongValue]];
}

- (void)notifyDelegateOfSuccess
{
	if ([delegate respondsToSelector:@selector(unarchiverDidFinish:)])
		[delegate performSelector:@selector(unarchiverDidFinish:) withObject:self];
}

- (void)notifyDelegateOfFailure
{
	if ([delegate respondsToSelector:@selector(unarchiverDidFail:)])
		[delegate performSelector:@selector(unarchiverDidFail:) withObject:self];
}

static NSMutableArray *gUnarchiverImplementations;

+ (void)registerImplementation:(Class)implementation
{
	if (!gUnarchiverImplementations)
		gUnarchiverImplementations = [[NSMutableArray alloc] init];
	[gUnarchiverImplementations addObject:implementation];
}

+ (NSArray *)unarchiverImplementations
{
	return [NSArray arrayWithArray:gUnarchiverImplementations];
}

@end
