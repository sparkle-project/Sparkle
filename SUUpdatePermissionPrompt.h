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

@protocol SUUpdatePermissionPromptDelegate;

@class SUHost;
@interface SUUpdatePermissionPrompt : SUWindowController {
	SUHost *host;
	NSArray *systemProfileInformationArray;
	id<SUUpdatePermissionPromptDelegate> delegate;
	IBOutlet NSTextField *descriptionTextField;
	IBOutlet NSView *moreInfoView;
	IBOutlet NSButton *moreInfoButton;
    IBOutlet NSTableView *profileTableView;
}
+ (void)promptWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile delegate:(id<SUUpdatePermissionPromptDelegate>)d;
- (IBAction)toggleMoreInfo:(id)sender;
- (IBAction)finishPrompt:(id)sender;
@end

@protocol SUUpdatePermissionPromptDelegate <NSObject>
- (void)updatePermissionPromptFinishedWithResult:(SUPermissionPromptResult)result;
@end

#endif
