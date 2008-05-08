//
//  SUAutomaticUpdateAlert.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAUTOMATICUPDATEALERT_H
#define SUAUTOMATICUPDATEALERT_H

#import "SUWindowController.h"

typedef enum
{
	SUInstallNowChoice,
	SUInstallLaterChoice,
	SUDoNotInstallChoice
} SUAutomaticInstallationChoice;

@class SUAppcastItem;
@interface SUAutomaticUpdateAlert : SUWindowController {
	SUAppcastItem *updateItem;
	id delegate;
	NSBundle *hostBundle;
}

- (id)initWithAppcastItem:(SUAppcastItem *)item hostBundle:(NSBundle *)hostBundle delegate:delegate;
- (IBAction)installNow:sender;
- (IBAction)installLater:sender;
- (IBAction)doNotInstall:sender;

@end

@interface NSObject (SUAutomaticUpdateAlertDelegateProtocol)
- (void)automaticUpdateAlert:(SUAutomaticUpdateAlert *)aua finishedWithChoice:(SUAutomaticInstallationChoice)choice;
@end

#endif
