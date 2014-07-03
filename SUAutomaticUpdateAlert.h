//
//  SUAutomaticUpdateAlert.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
// Additions by Yahoo:
// Copyright 2014 Yahoo Inc. Licensed under the project's open source license.
//
//

#ifndef SUAUTOMATICUPDATEALERT_H
#define SUAUTOMATICUPDATEALERT_H

#import "SUWindowController.h"

@protocol SUAutomaticUpdateAlertDelegateProtocol;

typedef enum
{
	SUInstallNowChoice,
	SUInstallLaterChoice,
	SUDoNotInstallChoice
} SUAutomaticInstallationChoice;

@class SUAppcastItem, SUHost;
@interface SUAutomaticUpdateAlert : SUWindowController {
	SUAppcastItem *updateItem;
	id<SUAutomaticUpdateAlertDelegateProtocol> delegate;
	SUHost *host;
    
    IBOutlet NSButton* cancelUpdate;
    IBOutlet NSButton* automaticUpdatesCheck;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)hostBundle delegate:(id<SUAutomaticUpdateAlertDelegateProtocol>)delegate;
- (IBAction)installNow:sender;
- (IBAction)installLater:sender;
- (IBAction)doNotInstall:sender;

@end

@protocol SUAutomaticUpdateAlertDelegateProtocol <NSObject>
- (void)automaticUpdateAlert:(SUAutomaticUpdateAlert *)aua finishedWithChoice:(SUAutomaticInstallationChoice)choice;
@end

#endif
