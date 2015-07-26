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

// Sparkle usually doesn't allow downgrades as they're usually accidental, but
//	if your app has a downgrade function or URL handler, turn this on:
#define PERMIT_AUTOMATED_DOWNGRADES					0

// If your app file on disk is named "MyApp 1.1b4", Sparkle usually updates it
//	in place, giving you an app named 1.1b4 that is actually 1.2. Turn the
//	following on to always reset the name back to "MyApp":
#define NORMALIZE_INSTALLED_APP_NAME				0

// When identifying updates to install from the downloaded update contents,
//  Sparkle by default searches for a folder in the downloaded directory which
//  matches the host app's file name, then looks for an installer package with
//  the same basename as the host app, and finally looks for a bundle with the
//  same identifier as the host app. There are some cases, however, when both
//  the update's file name and bundle identifier will be different -- notably,
//  when distributing an update that parallels what's just been made available
//  in the Mac App Store, which requires that apps have different bundle
//  identifiers and thus motivates changing both the app's name and
//  identifier. For cases like that, Sparkle can be more lax on bundle id
//  matching, and look for updates in the form of com.mycompany.myapp-2 or
//  com.mycompany.myapp3, which will match as valid updates to
//  com.mycompany.myapp. Turn the following on to allow for this more lax
//  bundle identifier validation.
#define FUZZY_BUNDLE_IDENTIFIER_MATCHING			1


#define TRY_TO_APPEND_VERSION_NUMBER				1

// -----------------------------------------------------------------------------
//	Notifications:
// -----------------------------------------------------------------------------

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
extern NSString *const SUExpectsDSASignatureKey;
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

#endif
