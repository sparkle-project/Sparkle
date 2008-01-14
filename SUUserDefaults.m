//
//  SUUserDefaults.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUUserDefaults.h"

@implementation SUUserDefaults

+ (SUUserDefaults *)standardUserDefaults
{
	static SUUserDefaults *standardUserDefaults = nil;
	if (standardUserDefaults == nil)
		standardUserDefaults = [[SUUserDefaults alloc] init];
	return standardUserDefaults;
}

- (void)dealloc
{
	[identifier release];
	[super dealloc];
}

- (void)setIdentifier:(NSString *)anIdentifier
{
	[identifier autorelease];
	identifier = [anIdentifier copy];
}

- (void)verifyIdentifier
{
	if (identifier == nil)
		[NSException raise:@"SUUserDefaultsMissingIdentifier" format:@"You must set the SUUserDefaults identifier before using it."];
}

- (id)objectForKey:(NSString *)defaultName
{
	[self verifyIdentifier];
	CFPropertyListRef obj = CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
#if MAC_OS_X_VERSION_MIN_REQUIRED > 1050
	return [NSMakeCollectable(obj) autorelease];
#else
	return [(id)obj autorelease];
#endif	
}

- (void)setObject:(id)value forKey:(NSString *)defaultName;
{
	[self verifyIdentifier];
	CFPreferencesSetValue((CFStringRef)defaultName, value, (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (BOOL)boolForKey:(NSString *)defaultName
{
	BOOL value;
	[self verifyIdentifier];
	CFPropertyListRef plr = CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	if (plr == NULL)
		value = NO;
	else {
		value = (BOOL)CFBooleanGetValue((CFBooleanRef)plr);
		CFRelease(plr);
	}
	
	return value;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName
{
	[self verifyIdentifier];
	CFPreferencesSetValue((CFStringRef)defaultName, (CFBooleanRef)[NSNumber numberWithBool:value], (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

@end
