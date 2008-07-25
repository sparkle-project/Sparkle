//
//  SUWindowController.m
//  Sparkle
//
//  Created by Andy Matuschak on 2/13/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUWindowController.h"

@implementation SUWindowController

- (id)initWithHost:(SUHost *)host windowNibName:(NSString *)nibName
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:nibName ofType:@"nib"];
	if (path == nil) // Slight hack to resolve issues with running Sparkle in debug configurations.
	{
		NSString *frameworkPath = [[host sharedFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		path = [framework pathForResource:nibName ofType:@"nib"];
	}
	return [super initWithWindowNibPath:path owner:self];	
}

@end
