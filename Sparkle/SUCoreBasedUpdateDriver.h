//
//  SUCoreBasedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUStatusCompletionResults.h"
#import "SUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;
@protocol SPUUpdaterDelegate;

@protocol SUCoreBasedUpdateDriverDelegate <NSObject>

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem;

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)willInstallSilently;

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

- (void)downloadDriverWillBeginDownload;

- (void)downloadDriverDidReceiveExpectedContentLength:(NSUInteger)expectedContentLength;

- (void)downloadDriverDidReceiveDataOfLength:(NSUInteger)length;

- (void)coreDriverDidStartExtractingUpdate;

- (void)installerDidStartInstalling;

- (void)installerDidExtractUpdateWithProgress:(double)progress;

- (void)installerIsRequestingAppTermination;

- (void)installerDidFinishInstallation;

@end

@interface SUCoreBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SUCoreBasedUpdateDriverDelegate>)delegate;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates requiresSilentInstall:(BOOL)silentInstall completion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock;

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem;

- (void)extractDownloadedUpdate;

- (void)clearDownloadedUpdate;

- (void)finishInstallationWithResponse:(SPUInstallUpdateStatus)installUpdateStatus displayingUserInterface:(BOOL)displayingUserInterface;

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
