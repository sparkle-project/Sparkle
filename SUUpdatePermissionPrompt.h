//
//  SUUpdatePermissionPrompt.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEPERMISSIONPROMPT_H
#define SUUPDATEPERMISSIONPROMPT_H

#import "SUWindowController.h"

typedef enum {
	SUAutomaticallyCheck,
	SUDoNotAutomaticallyCheck
} SUPermissionPromptResult;

@protocol SUUpdatePermissionPromptDelegateProtocol;

@class SUHost;
@interface SUUpdatePermissionPrompt : SUWindowController {
	SUHost *host;
	NSArray *systemProfileInformationArray;
	id<SUUpdatePermissionPromptDelegateProtocol> delegate;
	IBOutlet NSTextField *descriptionTextField;
	IBOutlet NSView *moreInfoView;
	IBOutlet NSButton *moreInfoButton;
    IBOutlet NSTableView *profileTableView;
	BOOL isShowingMoreInfo, shouldSendProfile;
}
+ (void)promptWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile delegate:(id<SUUpdatePermissionPromptDelegateProtocol>)d;
- (IBAction)toggleMoreInfo:(id)sender;
- (IBAction)finishPrompt:(id)sender;
@end

@protocol SUUpdatePermissionPromptDelegateProtocol <NSObject>
- (void)updatePermissionPromptFinishedWithResult:(SUPermissionPromptResult)result;
@end

#endif
