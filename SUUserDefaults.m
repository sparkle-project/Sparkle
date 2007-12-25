//
//  SUUserDefaults.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
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
	identifier = [anIdentifier copy];
}

- (void)verifyIdentifier
{
	if (identifier == nil)
		[NSException raise:@"SUUserDefaultsMissingIdentifier" format:@"You must set the SUUserDefaults identifier before using it."];
}

- objectForKey:(NSString *)defaultName
{
	[self verifyIdentifier];
	return (id)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
}

- (void)setObject:(id)value forKey:(NSString *)defaultName;
{
	[self verifyIdentifier];
	CFPreferencesSetValue((CFStringRef)defaultName, value, (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (BOOL)boolForKey:(NSString *)defaultName
{
	[self verifyIdentifier];
	CFPropertyListRef plr = (CFPropertyListRef)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	if (plr == NULL)
		return NO;
	else
		return CFBooleanGetValue((CFBooleanRef)plr);
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName
{
	[self verifyIdentifier];
	CFPreferencesSetValue((CFStringRef)defaultName, (CFBooleanRef)[NSNumber numberWithBool:value], (CFStringRef)identifier,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
	CFPreferencesSynchronize((CFStringRef)identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

@end
