//
//  SUBasicUpdateDriver.h
//  Sparkle,
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUBASICUPDATEDRIVER_H
#define SUBASICUPDATEDRIVER_H

#import "SUUpdateDriver.h"
#import "SPUDownloader.h"
#import "SPUDownloaderDelegate.h"

@class SUAppcast, SUAppcastItem, SUHost, SPUDownloadData;
@interface SUBasicUpdateDriver : SUUpdateDriver <SPUDownloaderDelegate>

@property (strong, readonly) SUAppcastItem *updateItem;
@property (strong, readonly) SUAppcastItem *latestAppcastItem;
@property (assign, readonly) NSComparisonResult latestAppcastItemComparisonResult;
@property (strong, readonly) SPUDownloader *download;
@property (copy, readonly) NSString *downloadPath;

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)host;

- (BOOL)isItemNewer:(SUAppcastItem *)ui;
- (BOOL)hostSupportsItem:(SUAppcastItem *)ui;
- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui;
- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui;
- (void)appcastDidFinishLoading:(SUAppcast *)ac;
- (void)didFindValidUpdate;
- (void)didNotFindUpdate;

- (void)downloadUpdate;
// SPUDownloaderDelegate
- (void)downloaderDidSetDestinationName:(NSString *)destinationName temporaryDirectory:(NSString *)temporaryDirectory;
- (void)downloaderDidReceiveExpectedContentLength:(int64_t)expectedContentLength;
- (void)downloaderDidReceiveDataOfLength:(uint64_t)length;
- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData *)downloadData;
- (void)downloaderDidFailWithError:(NSError *)error;

- (void)extractUpdate;
- (void)failedToApplyDeltaUpdate;

// Needed to preserve compatibility to subclasses, even though our unarchiver code uses blocks now
- (void)unarchiver:(id)ua extractedProgress:(double)progress;
- (void)unarchiverDidFinish:(id)ua;

- (void)installWithToolAndRelaunch:(BOOL)relaunch;
- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI;
- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error;

- (void)cleanUpDownload;

- (void)abortUpdate;
- (void)abortUpdateWithError:(NSError *)error;
- (void)terminateApp;

@end

#endif
