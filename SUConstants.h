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
#define ENDANGER_USERS_WITH_INSECURE_UPDATES		0

// Sparkle usually doesn't allow downgrades as they're usually accidental, but
//	if your app has a downgrade function or URL handler, turn this on:
#define PERMIT_AUTOMATED_DOWNGRADES					0

// If your app file on disk is named "MyApp 1.1b4", Sparkle usually updates it
//	in place, giving you an app named 1.1b4 that is actually 1.2. Turn the
//	following on to always reset the name back to "MyApp":
#define NORMALIZE_INSTALLED_APP_NAME				0


#define TRY_TO_APPEND_VERSION_NUMBER				1

// -----------------------------------------------------------------------------
//	Notifications:
// -----------------------------------------------------------------------------

extern NSString *const SUUpdaterWillRestartNotification;

extern NSString *const SUTechnicalErrorInformationKey;

// -----------------------------------------------------------------------------
//	PList keys::
// -----------------------------------------------------------------------------

extern NSString *const SUFeedURLKey;
extern NSString *const SUHasLaunchedBeforeKey;
extern NSString *const SUShowReleaseNotesKey;
extern NSString *const SUSkippedVersionKey;
extern NSString *const SUScheduledCheckIntervalKey;
extern NSString *const SULastCheckTimeKey;
extern NSString *const SUPublicDSAKeyKey;
extern NSString *const SUPublicDSAKeyFileKey;
extern NSString *const SUAutomaticallyUpdateKey;
extern NSString *const SUAllowsAutomaticUpdatesKey;
extern NSString *const SUEnableAutomaticChecksKey;
extern NSString *const SUEnableAutomaticChecksKeyOld;
extern NSString *const SUEnableSystemProfilingKey;
extern NSString *const SUSendProfileInfoKey;
extern NSString *const SULastProfileSubmitDateKey;
extern NSString *const SUPromptUserOnFirstLaunchKey;
extern NSString *const SUFixedHTMLDisplaySizeKey;
extern NSString *const SUKeepDownloadOnFailedInstallKey;
extern NSString *const SUDefaultsDomainKey;

// -----------------------------------------------------------------------------
//	Errors:
// -----------------------------------------------------------------------------

extern NSString *const SUSparkleErrorDomain;
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
