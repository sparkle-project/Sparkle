//
//  SUUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdateDriver.h"


@implementation SUUpdateDriver
- (void)checkForUpdatesAtURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hb
{
	[NSException raise:@"SUAbstractDriverError" format:@"Don't use SUUpdateDriver directly; use a subclass."];
}

- (void)abortUpdate
{
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"finished"];	
}

- (BOOL)finished { return finished; }
- delegate { return delegate; }
- (void)setDelegate:del { delegate = del; }
@end
