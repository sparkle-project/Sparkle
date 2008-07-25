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

@class SUHost;
@interface SUUpdateDriver : NSObject
{
	SUHost *host;
	
	BOOL finished;
}
- (void)checkForUpdatesAtURL:(NSURL *)appcastURL host:(SUHost *)host;
- (void)abortUpdate;
- (BOOL)finished;

@end

#endif
