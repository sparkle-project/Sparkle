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

typedef NS_ENUM(NSUInteger, SPUUserInitiatedCheckStatus) {
    SPUUserInitiatedCheckDone __deprecated_msg("Deprecated because SPUUserInitiatedCheckDone has no effect. Just don't reply with this status."),
    SPUUserInitiatedCheckCanceled
};

typedef NS_ENUM(NSUInteger, SPUDownloadUpdateStatus) {
    SPUDownloadUpdateDone __deprecated_msg("Deprecated because SPUDownloadUpdateDone has no effect. Just don't reply with this status."),
    SPUDownloadUpdateCanceled
};

typedef NS_ENUM(NSUInteger, SPUInstallUpdateStatus) {
    SPUInstallUpdateNow,
    SPUInstallAndRelaunchUpdateNow,
    SPUDismissUpdateInstallation
};

typedef NS_ENUM(NSInteger, SPUUpdateAlertChoice) {
    SPUInstallUpdateChoice,
    SPUInstallLaterChoice,
    SPUSkipThisVersionChoice
};

typedef NS_ENUM(NSInteger, SPUInformationalUpdateAlertChoice) {
    SPUDismissInformationalNoticeChoice,
    SPUSkipThisInformationalVersionChoice
};

#endif /* SPUStatusCompletionResults_h */
