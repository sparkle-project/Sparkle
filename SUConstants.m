//
//  SUConstants.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUConstants.h"

NSString *SUUpdaterWillRestartNotification = @"SUUpdaterWillRestartNotificationName";
NSString *SUTechnicalErrorInformationKey = @"SUTechnicalErrorInformation";

NSString *SUHasLaunchedBeforeKey = @"SUHasLaunchedBefore";
NSString *SUFeedURLKey = @"SUFeedURL";
NSString *SUShowReleaseNotesKey = @"SUShowReleaseNotes";
NSString *SUSkippedVersionKey = @"SUSkippedVersion";
NSString *SUScheduledCheckIntervalKey = @"SUScheduledCheckInterval";
NSString *SULastCheckTimeKey = @"SULastCheckTime";
NSString *SUExpectsDSASignatureKey = @"SUExpectsDSASignature";
NSString *SUPublicDSAKeyKey = @"SUPublicDSAKey";
NSString *SUPublicDSAKeyFileKey = @"SUPublicDSAKeyFile";
NSString *SUAutomaticallyUpdateKey = @"SUAutomaticallyUpdate";
NSString *SUAllowsAutomaticUpdatesKey = @"SUAllowsAutomaticUpdates";
NSString *SUEnableSystemProfilingKey = @"SUEnableSystemProfiling";
NSString *SUEnableAutomaticChecksKey = @"SUEnableAutomaticChecks";
NSString *SUEnableAutomaticChecksKeyOld = @"SUCheckAtStartup";
NSString *SUSendProfileInfoKey = @"SUSendProfileInfo";
NSString *SULastProfileSubmitDateKey = @"SULastProfileSubmissionDate";

NSString *SUSparkleErrorDomain = @"SUSparkleErrorDomain";
OSStatus SUAppcastParseError = 1000;
OSStatus SUNoUpdateError = 1001;
OSStatus SUAppcastError = 1002;
OSStatus SURunningFromDiskImageError = 1003;

OSStatus SUTemporaryDirectoryError = 2000;

OSStatus SUUnarchivingError = 3000;
OSStatus SUSignatureError = 3001;

OSStatus SUFileCopyFailure = 4000;
OSStatus SUAuthenticationFailure = 4001;
OSStatus SUMissingUpdateError = 4002;
OSStatus SUMissingInstallerToolError = 4003;
OSStatus SURelaunchError = 4004;
OSStatus SUInstallationError = 4005;
OSStatus SUDowngradeError = 4006;
