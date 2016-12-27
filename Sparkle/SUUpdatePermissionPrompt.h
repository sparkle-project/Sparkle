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

typedef NS_ENUM(NSInteger, SUPermissionPromptResult) {
    SUAutomaticallyCheck,
    SUDoNotAutomaticallyCheck
};

@protocol SUUpdatePermissionPromptDelegate;

@class SUHost, SUUpdatePermissionResponse;
@interface SUUpdatePermissionPrompt : SUWindowController

+ (void)promptWithHost:(SUHost *)host systemProfile:(NSArray *)profile reply:(void (^)(SUUpdatePermissionResponse *))reply;

- (IBAction)toggleMoreInfo:(id)sender;
- (IBAction)finishPrompt:(id)sender;
@end

#endif
