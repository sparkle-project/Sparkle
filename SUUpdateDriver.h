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

extern NSString *SUUpdateDriverFinishedNotification;

@interface SUUpdateDriver : NSObject
{
	BOOL finished;
	id delegate;
}
- (void)checkForUpdatesAtURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hb;
- (void)abortUpdate;
- (BOOL)finished;

- delegate;
- (void)setDelegate:delegate;
@end

#endif
