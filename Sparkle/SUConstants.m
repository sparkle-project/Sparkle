//
//  SUConstants.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUConstants.h"

NSString *const SUTechnicalErrorInformationKey = @"SUTechnicalErrorInformation";

NSString *const SUHasLaunchedBeforeKey = @"SUHasLaunchedBefore";
NSString *const SUFeedURLKey = @"SUFeedURL";
NSString *const SUShowReleaseNotesKey = @"SUShowReleaseNotes";
NSString *const SUSkippedVersionKey = @"SUSkippedVersion";
NSString *const SUScheduledCheckIntervalKey = @"SUScheduledCheckInterval";
NSString *const SULastCheckTimeKey = @"SULastCheckTime";
NSString *const SUExpectsDSASignatureKey = @"SUExpectsDSASignature";
NSString *const SUPublicDSAKeyKey = @"SUPublicDSAKey";
NSString *const SUPublicDSAKeyFileKey = @"SUPublicDSAKeyFile";
NSString *const SUAutomaticallyUpdateKey = @"SUAutomaticallyUpdate";
NSString *const SUAllowsAutomaticUpdatesKey = @"SUAllowsAutomaticUpdates";
NSString *const SUEnableSystemProfilingKey = @"SUEnableSystemProfiling";
NSString *const SUEnableAutomaticChecksKey = @"SUEnableAutomaticChecks";
NSString *const SUEnableAutomaticChecksKeyOld = @"SUCheckAtStartup";
NSString *const SUSendProfileInfoKey = @"SUSendProfileInfo";
NSString *const SULastProfileSubmitDateKey = @"SULastProfileSubmissionDate";
NSString *const SUPromptUserOnFirstLaunchKey = @"SUPromptUserOnFirstLaunch";
NSString *const SUFixedHTMLDisplaySizeKey = @"SUFixedHTMLDisplaySize";
NSString *const SUKeepDownloadOnFailedInstallKey = @"SUKeepDownloadOnFailedInstall";
NSString *const SUDefaultsDomainKey = @"SUDefaultsDomain";

NSString *const SUSparkleErrorDomain = @"SUSparkleErrorDomain";
