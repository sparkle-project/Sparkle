//
//  SUBasicUpdateDriver.h
//  Sparkle,
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUBASICUPDATEDRIVER_H
#define SUBASICUPDATEDRIVER_H

#import <Cocoa/Cocoa.h>
#import "SUUpdateDriver.h"

@class SUAppcastItem, SUUnarchiver, SUAppcast, SUUnarchiver;
@interface SUBasicUpdateDriver : SUUpdateDriver {
	NSBundle *hostBundle;
	SUAppcastItem *updateItem;
	
	NSURLDownload *download;
	NSString *downloadPath;
	
	SUUnarchiver *unarchiver;
	
	NSString *relaunchPath;
}

- (void)checkForUpdatesAtURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hb;

- (void)appcastDidFinishLoading:(SUAppcast *)ac;
- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error;

- (BOOL)isItemNewer:(SUAppcastItem *)ui;
- (BOOL)hostSupportsItem:(SUAppcastItem *)ui;
- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui;
- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui;
- (void)didFindValidUpdate;
- (void)didNotFindUpdate;

- (void)downloadUpdate;
- (void)download:(NSURLDownload *)d decideDestinationWithSuggestedFilename:(NSString *)name;
- (void)downloadDidFinish:(NSURLDownload *)d;
- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error;

- (void)extractUpdate;
- (void)unarchiverDidFinish:(SUUnarchiver *)ua;
- (void)unarchiverDidFail:(SUUnarchiver *)ua;

- (void)installUpdate;
- (void)installerFinishedForHostBundle:(NSBundle *)hb;
- (void)installerForHostBundle:(NSBundle *)hb failedWithError:(NSError *)error;
- (void)relaunchHostApp;

- (void)abortUpdate;
- (void)abortUpdateWithError:(NSError *)error;

@end

#endif
