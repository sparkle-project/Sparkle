//
//  SUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUProbingUpdateDriver.h"


@implementation SUProbingUpdateDriver

// Stop as soon as we have an answer! The superclasses will already have taken care of notifying the delegate.

- (void)didFindValidUpdate
{
	[self abortUpdate];
}

- (void)didNotFindUpdate
{
	[self abortUpdate];
}

@end
