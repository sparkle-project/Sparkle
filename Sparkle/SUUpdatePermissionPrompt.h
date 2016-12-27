//
//  SUUpdatePermissionPrompt.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEPERMISSIONPROMPT_H
#define SUUPDATEPERMISSIONPROMPT_H

#import <Cocoa/Cocoa.h>

@class SUHost, SPUUpdatePermissionRequest, SUUpdatePermissionResponse;

@interface SUUpdatePermissionPrompt : NSWindowController

+ (void)promptWithHost:(SUHost *)host request:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply;

- (IBAction)toggleMoreInfo:(id)sender;
- (IBAction)finishPrompt:(id)sender;
@end

#endif
