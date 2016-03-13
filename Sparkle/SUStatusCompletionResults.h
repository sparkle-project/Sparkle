//
//  SUStatusCompletionResults.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/29/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SUStatusCompletionResults_h
#define SUStatusCompletionResults_h

#import <Foundation/Foundation.h>

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
    SUDismissUpdateInstallation
};

typedef NS_ENUM(NSInteger, SUUpdateAlertChoice) {
    SUInstallUpdateChoice,
    SUInstallLaterChoice,
    SUSkipThisVersionChoice
};

#endif /* SUStatusCompletionResults_h */
