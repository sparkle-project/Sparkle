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
@synthesize delegate;

+ (SUUnarchiver *)unarchiverForPath:(NSString *)path updatingHost:(SUHost *)host
{
	for (id current in [self unarchiverImplementations])
	{
		if ([current canUnarchivePath:path])
			return [[[current alloc] initWithPath:path host:host] autorelease];
	}
	return nil;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], archivePath]; }

- (void)start
{
	// No-op
}

@end
