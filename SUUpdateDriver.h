//
//  SUUpdateDriver.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEDRIVER_H
#define SUUPDATEDRIVER_H

#import <Cocoa/Cocoa.h>

extern NSString * const SUUpdateDriverFinishedNotification;

@class SUHost, SUUpdater;
@interface SUUpdateDriver : NSObject
{
	SUHost *host;
	SUUpdater *updater;
	NSURL *appcastURL;
	
	SUUpdateAbortReason abortReason;
}

- (id)initWithUpdater:(SUUpdater *)updater;
- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)host;
- (void)abortUpdate:(SUUpdateAbortReason)reason;
- (BOOL)finished;
- (SUHost*)host;
- (void)setHost:(SUHost*)newHost;
- (SUUpdateAbortReason)abortReason;
- (BOOL)shouldShowUI; // can change it's value

@end

#endif
