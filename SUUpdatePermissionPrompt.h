//
//  SUUpdatePermissionPrompt.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEPERMISSIONPROMPT_H
#define SUUPDATEPERMISSIONPROMPT_H

#import "Sparkle.h"

typedef enum {
	SUAutomaticallyCheck,
	SUDoNotAutomaticallyCheck
} SUPermissionPromptResult;

@interface SUUpdatePermissionPrompt : SUWindowController {
	NSBundle *hostBundle;
	id delegate;
	IBOutlet NSTextField *descriptionTextField;
	IBOutlet NSView *moreInfoView;
	IBOutlet NSButton *moreInfoButton;
	BOOL isShowingMoreInfo, shouldSendProfile;
}
+ (void)promptWithHostBundle:(NSBundle *)hb delegate:(id)d;
- (IBAction)toggleMoreInfo:(id)sender;
- (IBAction)finishPrompt:(id)sender;
@end

@interface NSObject (SUUpdatePermissionPromptDelegateInformalProtocol)
- (void)updatePermissionPromptFinishedWithResult:(SUPermissionPromptResult)result;
@end

#endif
