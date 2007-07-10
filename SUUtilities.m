//
//  SUUtilities.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUtilities.h"

@interface SUUtilities : NSObject
	+(NSString *)localizedStringForKey:(NSString *)key withComment:(NSString *)comment;
@end

id SUUnlocalizedInfoValueForKey(NSString *key)
{
	// Okay, but if it isn't there, let's use the general one.
	id value = [[[NSBundle mainBundle] infoDictionary] valueForKey:key];
	if (!value)
		return SUInfoValueForKey(key);
	return value;
}

id SUInfoValueForKey(NSString *key)
{
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
}

NSString *SUHostAppName()
{
	if (SUInfoValueForKey(@"CFBundleName")) { return SUInfoValueForKey(@"CFBundleName"); }
	return [[[NSFileManager defaultManager] displayNameAtPath:[[NSBundle mainBundle] bundlePath]] stringByDeletingPathExtension];
}

NSString *SUHostAppDisplayName()
{
	if (SUInfoValueForKey(@"CFBundleDisplayName")) { return SUInfoValueForKey(@"CFBundleDisplayName"); }
	return SUHostAppName();
}

NSString *SUHostAppVersion()
{
	return SUInfoValueForKey(@"CFBundleVersion");
}

NSString *SUHostAppVersionString()
{
	NSString *shortVersionString = SUInfoValueForKey(@"CFBundleShortVersionString");
	if (shortVersionString)
	{
		if (![shortVersionString isEqualToString:SUHostAppVersion()])
			shortVersionString = [shortVersionString stringByAppendingFormat:@"/%@", SUHostAppVersion()];
		return shortVersionString;
	}
	else
		return SUHostAppVersion(); // fall back on CFBundleVersion
}

NSString *SULocalizedString(NSString *key, NSString *comment) {
	return [SUUtilities localizedStringForKey:key withComment:comment];
}

enum {
    kNumberType,
    kStringType,
    kPeriodType
};

// The version comparison code here is courtesy of Kevin Ballard, adapted from MacPAD. Thanks, Kevin!

int SUGetCharType(NSString *character)
{
    if ([character isEqualToString:@"."]) {
        return kPeriodType;
    } else if ([character isEqualToString:@"0"] || [character intValue] != 0) {
        return kNumberType;
    } else {
        return kStringType;
    }	
}

NSArray *SUSplitVersionString(NSString *version)
{
    NSString *character;
    NSMutableString *s;
    int i, n, oldType, newType;
    NSMutableArray *parts = [NSMutableArray array];
    if ([version length] == 0) {
        // Nothing to do here
        return parts;
    }
    s = [[[version substringToIndex:1] mutableCopy] autorelease];
    oldType = SUGetCharType(s);
    n = [version length] - 1;
    for (i = 1; i <= n; ++i) {
        character = [version substringWithRange:NSMakeRange(i, 1)];
        newType = SUGetCharType(character);
        if (oldType != newType || oldType == kPeriodType) {
            // We've reached a new segment
			NSString *aPart = [[NSString alloc] initWithString:s];
            [parts addObject:aPart];
			[aPart release];
            [s setString:character];
        } else {
            // Add character to string and continue
            [s appendString:character];
        }
        oldType = newType;
    }
    
    // Add the last part onto the array
    [parts addObject:[NSString stringWithString:s]];
    return parts;
}

NSComparisonResult SUStandardVersionComparison(NSString *versionA, NSString *versionB)
{
	NSArray *partsA = SUSplitVersionString(versionA);
    NSArray *partsB = SUSplitVersionString(versionB);
    
    NSString *partA, *partB;
    int i, n, typeA, typeB, intA, intB;
    
    n = MIN([partsA count], [partsB count]);
    for (i = 0; i < n; ++i) {
        partA = [partsA objectAtIndex:i];
        partB = [partsB objectAtIndex:i];
        
        typeA = SUGetCharType(partA);
        typeB = SUGetCharType(partB);
        
        // Compare types
        if (typeA == typeB) {
            // Same type; we can compare
            if (typeA == kNumberType) {
                intA = [partA intValue];
                intB = [partB intValue];
                if (intA > intB) {
                    return NSOrderedAscending;
                } else if (intA < intB) {
                    return NSOrderedDescending;
                }
            } else if (typeA == kStringType) {
                NSComparisonResult result = [partB compare:partA];
                if (result != NSOrderedSame) {
                    return result;
                }
            }
        } else {
            // Not the same type? Now we have to do some validity checking
            if (typeA != kStringType && typeB == kStringType) {
                // typeA wins
                return NSOrderedAscending;
            } else if (typeA == kStringType && typeB != kStringType) {
                // typeB wins
                return NSOrderedDescending;
            } else {
                // One is a number and the other is a period. The period is invalid
                if (typeA == kNumberType) {
                    return NSOrderedAscending;
                } else {
                    return NSOrderedDescending;
                }
            }
        }
    }
    // The versions are equal up to the point where they both still have parts
    // Lets check to see if one is larger than the other
    if ([partsA count] != [partsB count]) {
        // Yep. Lets get the next part of the larger
        // n holds the value we want
        NSString *missingPart;
        int missingType, shorterResult, largerResult;
        
        if ([partsA count] > [partsB count]) {
            missingPart = [partsA objectAtIndex:n];
            shorterResult = NSOrderedDescending;
            largerResult = NSOrderedAscending;
        } else {
            missingPart = [partsB objectAtIndex:n];
            shorterResult = NSOrderedAscending;
            largerResult = NSOrderedDescending;
        }
        
        missingType = SUGetCharType(missingPart);
        // Check the type
        if (missingType == kStringType) {
            // It's a string. Shorter version wins
            return shorterResult;
        } else {
            // It's a number/period. Larger version wins
            return largerResult;
        }
    }
    
    // The 2 strings are identical
    return NSOrderedSame;
}

@implementation SUUtilities

+ (NSString *)localizedStringForKey:(NSString *)key withComment:(NSString *)comment 
{
	return NSLocalizedStringFromTableInBundle(key, @"Sparkle", [NSBundle bundleForClass:[self class]], comment);
}

@end
