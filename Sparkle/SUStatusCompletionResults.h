//
//  SUStatusCompletionResults.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/29/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SUStatusCompletionResults_h
#define SUStatusCompletionResults_h

typedef NS_ENUM(NSUInteger, SUUpdateCheckTimerStatus) {
    SUCheckForUpdateNow,
    SUCheckForUpdateWillOccurLater
};

typedef NS_ENUM(NSUInteger, SUUserInitiatedCheckStatus) {
    SUUserInitiatedCheckDone,
    SUUserInitiatedCheckCancelled
};

typedef NS_ENUM(NSUInteger, SUDownloadUpdateStatus) {
    SUDownloadUpdateDone,
    SUDownloadUpdateCancelled
};

typedef NS_ENUM(NSUInteger, SUApplicationTerminationStatus) {
    SUApplicationWillTerminate,
    SUApplicationStoppedObservingTermination
};

typedef NS_ENUM(NSUInteger, SUSystemPowerOffStatus) {
    SUSystemWillPowerOff,
    SUStoppedObservingSystemPowerOff
};

typedef NS_ENUM(NSUInteger, SUInstallUpdateStatus) {
    SUInstallAndRelaunchUpdateNow,
    SUCancelUpdateInstallation
};

typedef NS_ENUM(NSInteger, SUUpdateAlertChoice) {
    SUInstallUpdateChoice,
    SURemindMeLaterChoice,
    SUSkipThisVersionChoice
};

typedef NS_ENUM(NSInteger, SUAutomaticInstallationChoice) {
    SUInstallNowChoice,
    SUInstallLaterChoice,
    SUDoNotInstallChoice
};

#endif /* SUStatusCompletionResults_h */
