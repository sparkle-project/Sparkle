//
//  SUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUProbingUpdateDriver.h"


@implementation SUProbingUpdateDriver

- (void)didFindValidUpdate
{
	if ([delegate respondsToSelector:@selector(didFindValidUpdate:toHostBundle:)])
		[delegate didFindValidUpdate:updateItem toHostBundle:hostBundle];
	[self abortUpdate];
}

- (void)didNotFindUpdate
{
	if ([delegate respondsToSelector:@selector(didNotFindUpdateToHostBundle:)])
		[delegate didNotFindUpdateToHostBundle:hostBundle];
	[self abortUpdate];
}

@end
