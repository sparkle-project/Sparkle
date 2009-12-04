//
//  SUConstants.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#ifndef SUCONSTANTS_H
#define SUCONSTANTS_H

// -----------------------------------------------------------------------------
//	Preprocessor flags:
// -----------------------------------------------------------------------------

// Turn off DSA signature check (practically invites man-in-the-middle attacks):
#define ENDANGER_USERS_WITH_INSECURE_UPDATES		1

// Sparkle usually doesn't allow downgrades as they're usually accidental, but
//	if your app has a downgrade function or URL handler, turn this on:
#define PERMIT_AUTOMATED_DOWNGRADES					1

// If your app file on disk is named "MyApp 1.1b4", Sparkle usually updates it
//	in place, giving you an app named 1.1b4 that is actually 1.2. Turn the
//	following on to always reset the name back to "MyApp":
#define NORMALIZE_INSTALLED_APP_NAME				1

// -----------------------------------------------------------------------------
//	Notifications:
// -----------------------------------------------------------------------------

extern NSString *SUUpdaterWillRestartNotification;

extern NSString *SUTechnicalErrorInformationKey;

// -----------------------------------------------------------------------------
//	PList keys::
// -----------------------------------------------------------------------------

extern NSString *SUFeedURLKey;
extern NSString *SUHasLaunchedBeforeKey;
extern NSString *SUShowReleaseNotesKey;
extern NSString *SUSkippedVersionKey;
extern NSString *SUScheduledCheckIntervalKey;
extern NSString *SULastCheckTimeKey;
extern NSString *SUPublicDSAKeyKey;
extern NSString *SUPublicDSAKeyFileKey;
extern NSString *SUAutomaticallyUpdateKey;
extern NSString *SUAllowsAutomaticUpdatesKey;
extern NSString *SUEnableAutomaticChecksKey;
extern NSString *SUEnableAutomaticChecksKeyOld;
extern NSString *SUEnableSystemProfilingKey;
extern NSString *SUSendProfileInfoKey;
extern NSString *SULastProfileSubmitDateKey;
extern NSString *SUFixedHTMLDisplaySizeKey;
extern NSString *SUKeepDownloadOnFailedInstallKey;

// -----------------------------------------------------------------------------
//	Errors:
// -----------------------------------------------------------------------------

extern NSString *SUSparkleErrorDomain;
// Appcast phase errors.
extern OSStatus SUAppcastParseError;
extern OSStatus SUNoUpdateError;
extern OSStatus SUAppcastError;
extern OSStatus SURunningFromDiskImageError;

// Downlaod phase errors.
extern OSStatus SUTemporaryDirectoryError;

// Extraction phase errors.
extern OSStatus SUUnarchivingError;
extern OSStatus SUSignatureError;

// Installation phase errors.
extern OSStatus SUFileCopyFailure;
extern OSStatus SUAuthenticationFailure;
extern OSStatus SUMissingUpdateError;
extern OSStatus SUMissingInstallerToolError;
extern OSStatus SURelaunchError;
extern OSStatus SUInstallationError;
extern OSStatus SUDowngradeError;


// -----------------------------------------------------------------------------
//	NSInteger fixer-upper:
// -----------------------------------------------------------------------------

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
