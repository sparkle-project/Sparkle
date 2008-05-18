//
//  NSNumber+Units.m
//  Sparkle
//
//  Created by Jonas Witt on 5/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "NSNumber+Units.h"


@implementation NSNumber (Units)

+ (NSString *)humanReadableSizeFromDouble:(double)value
{
	if (value < 1024)
		return [NSString stringWithFormat:@"%ul", value];
	
	if (value < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0lf KB", value / 1024.0];

	if (value < 1024 * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1lf MB", value / 1024.0 / 1024.0];

	return [NSString stringWithFormat:@"%.2lf GB", value / 1024.0 / 1024.0 / 1024.0];
}

@end
