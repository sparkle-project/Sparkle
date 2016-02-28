//
//  SUUpdateDriver.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEDRIVER_H
#define SUUPDATEDRIVER_H

#import <Foundation/Foundation.h>

extern NSString *const SUUpdateDriverFinishedNotification;

@class SUHost, SUUpdater;
@interface SUUpdateDriver : NSObject <NSURLDownloadDelegate>

@property (readonly, weak) SUUpdater *updater;
@property (strong) SUHost *host;

- (instancetype)initWithUpdater:(SUUpdater *)updater host:(SUHost *)host;
- (void)checkForUpdatesAtURL:(NSURL *)URL;
- (void)abortUpdate;

@property (getter=isInterruptible, readonly) BOOL interruptible;
@property (readonly) BOOL finished;
@property BOOL automaticallyInstallUpdates;

@end

#endif
