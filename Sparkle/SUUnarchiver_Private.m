//
//  SUUnarchiver_Private.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/17/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUnarchiver_Private.h"
#import "SUHost.h"

@implementation SUUnarchiver (Private)

- (instancetype)initWithPath:(NSString *)path host:(SUHost *)host
{
	if ((self = [super init]))
	{
		archivePath = [path copy];
		updateHost = host;
	}
	return self;
}

+ (BOOL)canUnarchivePath:(NSString *) __unused path
{
	return NO;
}

- (void)notifyDelegateOfExtractedLength:(size_t)length
{
    if ([self.delegate respondsToSelector:@selector(unarchiver:extractedLength:)]) {
        [self.delegate unarchiver:self extractedLength:length];
	}
}

- (void)notifyDelegateOfSuccess
{
    if ([self.delegate respondsToSelector:@selector(unarchiverDidFinish:)]) {
        [self.delegate unarchiverDidFinish:self];
	}
}

- (void)notifyDelegateOfFailure
{
    if ([self.delegate respondsToSelector:@selector(unarchiverDidFail:)]) {
        [self.delegate unarchiverDidFail:self];
	}
}

static NSMutableArray *gUnarchiverImplementations;

+ (void)registerImplementation:(Class)implementation
{
	if (!gUnarchiverImplementations) {
		gUnarchiverImplementations = [[NSMutableArray alloc] init];
	}
	[gUnarchiverImplementations addObject:implementation];
}

+ (NSArray *)unarchiverImplementations
{
	return [NSArray arrayWithArray:gUnarchiverImplementations];
}

@end
