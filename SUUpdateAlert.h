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


typedef enum
{
	SUInstallUpdateChoice,
	SURemindMeLaterChoice,
	SUSkipThisVersionChoice,
	SUOpenInfoURLChoice
} SUUpdateAlertChoice;

@class WebView, SUAppcastItem, SUHost;
@interface SUUpdateAlert : SUWindowController {
	SUAppcastItem *updateItem;
	SUHost *host;
	id delegate;
	id<SUVersionDisplay>	versionDisplayer;
	
	IBOutlet WebView *releaseNotesView;
	IBOutlet NSTextField *description;
	IBOutlet NSButton *installButton;	// UK 2007-08-31.
	IBOutlet NSButton *skipButton;
	IBOutlet NSButton *laterButton;
	NSProgressIndicator *releaseNotesSpinner;
	BOOL webViewFinishedLoading;
}

- (id)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)host;
- (void)setDelegate:delegate;

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;

- (void)setVersionDisplayer: (id<SUVersionDisplay>)disp;

@end

@interface NSObject (SUUpdateAlertDelegate)
- (void)updateAlert:(SUUpdateAlert *)updateAlert finishedWithChoice:(SUUpdateAlertChoice)updateChoice;
- (void)updateAlert:(SUUpdateAlert *)updateAlert shouldAllowAutoUpdate: (BOOL*)shouldAllowAutoUpdate;
@end

#endif
