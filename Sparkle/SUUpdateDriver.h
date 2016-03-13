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

@protocol SUUpdaterDelegate, SUUserDriver;
@class SUHost, SUUpdater;

@interface SUUpdateDriver : NSObject <NSURLDownloadDelegate>

@property (readonly, weak) id updater;
@property (strong) SUHost *host;
@property (nonatomic, readonly, weak) id<SUUpdaterDelegate> updaterDelegate;
@property (nonatomic, readonly) id<SUUserDriver> userDriver;
@property (nonatomic, readonly) NSBundle *sparkleBundle;

- (instancetype)initWithUpdater:(id)updater updaterDelegate:(id<SUUpdaterDelegate>)updaterDelegate userDriver:(id<SUUserDriver>)userDriver host:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle;
- (void)checkForUpdatesAtURL:(NSURL *)URL;
- (void)abortUpdate;

@property (getter=isInterruptible, readonly) BOOL interruptible;
@property (readonly) BOOL finished;
@property BOOL automaticallyInstallUpdates;

@end

#endif
