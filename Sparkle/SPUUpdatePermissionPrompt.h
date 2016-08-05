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

@class SUHost, SPUUpdatePermission;

@interface SPUUpdatePermissionPrompt : NSWindowController

+ (void)promptWithHost:(SUHost *)host systemProfile:(NSArray *)systemProfile reply:(void (^)(SPUUpdatePermission *))reply;

- (IBAction)toggleMoreInfo:(id)sender;
- (IBAction)finishPrompt:(id)sender;
@end

#endif
