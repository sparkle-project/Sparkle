//
//  SUUpdateAlert.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEALERT_H
#define SUUPDATEALERT_H

#import <WebKit/WebKit.h>
#import "SUWindowController.h"
#import "SUVersionDisplayProtocol.h"

// WebKit protocols are not explicitly declared until 10.11 SDK, so
// declare dummy protocols to keep the build working on earlier SDKs.
#if !defined(MAC_OS_X_VERSION_10_11)
@protocol WebFrameLoadDelegate
@end
@protocol WebPolicyDelegate
@end
#endif

@protocol SUUpdateAlertDelegate;

typedef NS_ENUM(NSInteger, SUUpdateAlertChoice) {
    SUInstallUpdateChoice,
    SURemindMeLaterChoice,
    SUSkipThisVersionChoice,
    SUOpenInfoURLChoice
};

@class WebView, SUAppcastItem, SUHost;
@interface SUUpdateAlert : SUWindowController <WebFrameLoadDelegate, WebPolicyDelegate>

@property (weak) id<SUVersionDisplay> versionDisplayer;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)host completionBlock:(void(^)(SUUpdateAlertChoice))c;

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;

@end

#endif
