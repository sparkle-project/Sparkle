//
//  SUConstants.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#ifndef SUCONSTANTS_H
#define SUCONSTANTS_H


extern NSString *SUUpdaterWillRestartNotification;

extern NSString *SUFeedURLKey;
extern NSString *SUHasLaunchedBeforeKey;
extern NSString *SUShowReleaseNotesKey;
extern NSString *SUSkippedVersionKey;
extern NSString *SUScheduledCheckIntervalKey;
extern NSString *SULastCheckTimeKey;
extern NSString *SUExpectsDSASignatureKey;
extern NSString *SUPublicDSAKeyKey;
extern NSString *SUAutomaticallyUpdateKey;
extern NSString *SUAllowsAutomaticUpdatesKey;
extern NSString *SUEnableAutomaticChecksKey;
extern NSString *SUSendProfileInfoKey;

// NSInteger is a type that was added to Leopard.
// Here is some glue to ensure that NSInteger will work with pre-10.5 SDKs:
#ifndef NSINTEGER_DEFINED
	#ifdef NS_BUILD_32_LIKE_64
		typedef long NSInteger;
		typedef unsigned long NSUInteger;
	#else
		typedef int NSInteger;
		typedef unsigned int NSUInteger;
	#endif
	#define NSIntegerMax    LONG_MAX
	#define NSIntegerMin    LONG_MIN
	#define NSUIntegerMax   ULONG_MAX
	#define NSINTEGER_DEFINED 1
#endif


#endif
