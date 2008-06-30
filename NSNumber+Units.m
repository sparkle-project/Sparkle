//
//  NSNumber+Units.m
//  Sparkle
//
//  Created by Jonas Witt on 5/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "NSNumber+Units.h"
#import "Sparkle.h"

@implementation NSNumber (JWUnits)

+ (NSString *)humanReadableSizeFromDouble:(double)value
{
	if (value < 1024)
		return [NSString stringWithFormat:@"%.0lf %@", value, SULocalizedString(@"B", @"the unit for bytes")];
	
	if (value < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0lf %@", value / 1024.0, SULocalizedString(@"KB", @"the unit for kilobytes")];

	if (value < 1024 * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1lf %@", value / 1024.0 / 1024.0, SULocalizedString(@"MB", @"the unit for megabytes")];

	return [NSString stringWithFormat:@"%.2lf %@", value / 1024.0 / 1024.0 / 1024.0, SULocalizedString(@"GB", @"the unit for gigabytes")];
}

@end
