//
//  NSURL+Parameters.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "NSURL+Parameters.h"

@implementation NSURL (SUParameterAdditions)
- (NSURL *)URLWithParameters:(NSArray *)parameters;
{
	if (parameters == nil || [parameters count] == 0) { return self; }
	NSMutableArray *profileInfo = [NSMutableArray array];
	NSEnumerator *profileInfoEnumerator = [parameters objectEnumerator];
	NSDictionary *currentProfileInfo;
	while ((currentProfileInfo = [profileInfoEnumerator nextObject])) {
		[profileInfo addObject:[NSString stringWithFormat:@"%@=%@", [currentProfileInfo objectForKey:@"key"], [currentProfileInfo objectForKey:@"value"]]];
	}
	
	NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@?%@", [self absoluteString], [profileInfo componentsJoinedByString:@"&"]];
	
	// Clean it up so it's a valid URL
	return [NSURL URLWithString:[appcastStringWithProfile stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}
@end
