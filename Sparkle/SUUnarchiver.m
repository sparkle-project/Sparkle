//
//  SUUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUUnarchiver.h"
#import "SUUnarchiver_Private.h"

@implementation SUUnarchiver

@synthesize archivePath;
@synthesize updateHost;
@synthesize delegate;

+ (SUUnarchiver *)unarchiverForPath:(NSString *)path updatingHost:(SUHost *)host
{
	for (id current in [self unarchiverImplementations])
	{
        if ([current canUnarchivePath:path]) {
            return [[current alloc] initWithPath:path host:host];
        }
    }
    return nil;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

- (void)start
{
    // No-op
}

- (instancetype)initWithPath:(NSString *)path host:(SUHost *)host
{
    if ((self = [super init]))
    {
        archivePath = [path copy];
        updateHost = host;
    }
    return self;
}

+ (BOOL)canUnarchivePath:(NSString *)__unused path
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
