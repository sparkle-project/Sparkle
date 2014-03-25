//
//  SUAppcastItem.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCASTITEM_H
#define SUAPPCASTITEM_H

@interface SUAppcastItem : NSObject
{
@private
	NSString *title;
	NSDate *date;
	NSString *itemDescription;
	
	NSURL *releaseNotesURL;
	
	NSString *DSASignature;	
	NSString *minimumSystemVersion;
    NSString *maximumSystemVersion;
	
	NSURL *fileURL;
	 
	NSString *versionString;
	NSString *displayVersionString;

	NSDictionary *deltaUpdates;

	NSDictionary *propertiesDictionary;
	
	NSURL *infoURL;	// UK 2007-08-31
}

// Initializes with data from a dictionary provided by the RSS class.
- initWithDictionary:(NSDictionary *)dict;
- initWithDictionary:(NSDictionary *)dict failureReason:(NSString**)error;

- (NSString *)title;
- (NSString *)versionString;
- (NSString *)displayVersionString;
- (NSDate *)date;
- (NSString *)itemDescription;
- (NSURL *)releaseNotesURL;
- (NSURL *)fileURL;
- (NSString *)DSASignature;
- (NSString *)minimumSystemVersion;
- (NSString *)maximumSystemVersion;
- (NSDictionary *)deltaUpdates;
- (BOOL)isDeltaUpdate;

// Returns the dictionary provided in initWithDictionary; this might be useful later for extensions.
- (NSDictionary *)propertiesDictionary;

- (NSURL *)infoURL;						// UK 2007-08-31

// Used to inform the behavior of the UI e.g. when presenting news of an update
// to the user. Here is where logic for what makes an update "informational only"
// can be overridden to ensure that the user is presented with appropriate language,
// that the button changes from "Install" to "Learn More..." etc.
- (BOOL) isInformationOnlyUpdate;

@end

#endif
