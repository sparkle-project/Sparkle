//
//  SUUpdateAlert.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEALERT_H
#define SUUPDATEALERT_H

#import "SUWindowController.h"
#import "SUVersionDisplayProtocol.h"

@protocol SUUpdateAlertDelegate;

typedef enum
{
    SUInstallUpdateChoice,
    SURemindMeLaterChoice,
    SUSkipThisVersionChoice,
    SUOpenInfoURLChoice
} SUUpdateAlertChoice;

@class WebView, SUAppcastItem, SUHost;
@interface SUUpdateAlert : SUWindowController

@property (weak) id<SUUpdateAlertDelegate> delegate;
@property (weak) id<SUVersionDisplay> versionDisplayer;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)host;

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;

@end

@protocol SUUpdateAlertDelegate <NSObject>
- (void)updateAlert:(SUUpdateAlert *)updateAlert finishedWithChoice:(SUUpdateAlertChoice)updateChoice;
@optional
- (void)updateAlert:(SUUpdateAlert *)updateAlert shouldAllowAutoUpdate:(BOOL *)shouldAllowAutoUpdate;
@end

#endif
