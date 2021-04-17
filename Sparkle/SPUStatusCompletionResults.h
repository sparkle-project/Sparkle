//
//  SPUStatusCompletionResults.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/29/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SPUStatusCompletionResults_h
#define SPUStatusCompletionResults_h

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

// The value ordering here intentionally aligns with replacing SPUInstallUpdateStatus
typedef NS_ENUM(NSInteger, SPUUserUpdateChoice) {
    SPUUserUpdateChoiceSkip,
    SPUUserUpdateChoiceInstall,
    SPUUserUpdateChoiceDismiss,
};

typedef NS_ENUM(NSInteger, SPUUserUpdateState) {
    SPUUserUpdateStateNotDownloaded,
    SPUUserUpdateStateDownloaded,
    SPUUserUpdateStateInstalling,
    SPUUserUpdateStateInformational
};

// Deprecated
typedef NS_ENUM(NSInteger, SPUInformationalUpdateAlertChoice) {
    SPUDismissInformationalNoticeChoice,
    SPUSkipThisInformationalVersionChoice
};

// Deprecated
typedef NS_ENUM(NSUInteger, SPUInstallUpdateStatus) {
    SPUInstallUpdateNow,
    SPUInstallAndRelaunchUpdateNow,
    SPUDismissUpdateInstallation
};

// Deprecated
typedef NS_ENUM(NSInteger, SPUUpdateAlertChoice) {
    SPUInstallUpdateChoice,
    SPUInstallLaterChoice,
    SPUSkipThisVersionChoice
};

// Deprecated
typedef NS_ENUM(NSUInteger, SPUUserInitiatedCheckStatus) {
    SPUUserInitiatedCheckDone,
    SPUUserInitiatedCheckCanceled
};

// Deprecated
typedef NS_ENUM(NSUInteger, SPUDownloadUpdateStatus) {
    SPUDownloadUpdateDone,
    SPUDownloadUpdateCanceled
};

#endif /* SPUStatusCompletionResults_h */
