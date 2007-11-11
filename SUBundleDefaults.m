//
//  SUBundleDefaults.m
//  Sparkle
//
//  Created by Christopher Atlan on 07.11.07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "SUBundleDefaults.h"
#import "SUUtilities.h"

@implementation SUBundleDefaults

- (id)initWithUtilitie:(SUUtilities *)theUtilities
{
	self = [super init];
	if (self != nil) {
		utilities = [theUtilities retain];
		applicationID = [utilities hostAppID];
	}
	return self;
}

- (void) dealloc
{
	[utilities release];
	[applicationID release];
	[super dealloc];
}


- (id)objectForKey:(NSString *)defaultName
{
	return (id)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

- (void)setObject:(id)value forKey:(NSString *)defaultName;
{
	CFPreferencesSetValue((CFStringRef)defaultName, value, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (void)removeObjectForKey:(NSString *)defaultName
{
	CFPreferencesSetValue((CFStringRef)defaultName, NULL, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (NSString *)stringForKey:(NSString *)defaultName
{
	return (NSString *)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

- (NSArray *)arrayForKey:(NSString *)defaultName
{
	return (NSArray *)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

- (NSDictionary *)dictionaryForKey:(NSString *)defaultName
{
	return (NSDictionary *)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

- (NSData *)dataForKey:(NSString *)defaultName
{
	return (NSData *)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

- (NSArray *)stringArrayForKey:(NSString *)defaultName
{
	return (NSArray *)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

/*
- (int)integerForKey:(NSString *)defaultName; 
- (float)floatForKey:(NSString *)defaultName; 
*/

- (BOOL)boolForKey:(NSString *)defaultName
{
	CFPropertyListRef plr = (CFPropertyListRef)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	if (plr == NULL)
		return NO;
	return CFBooleanGetValue((CFBooleanRef)plr);
}
 
/*
- (void)setInteger:(int)value forKey:(NSString *)defaultName;
- (void)setFloat:(float)value forKey:(NSString *)defaultName;
*/

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName
{
	CFPreferencesSetValue((CFStringRef)defaultName, (CFBooleanRef)[NSNumber numberWithBool:value], (CFStringRef)applicationID,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

@end
