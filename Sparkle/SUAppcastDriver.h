//
//  SUAppcastDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem, SUHost, SUAppcast;
@protocol SPUUpdaterDelegate;

@protocol SUAppcastDriverDelegate <NSObject>

- (void)didFailToFetchAppcastWithError:(NSError *)error;
- (void)didFinishLoadingAppcast:(SUAppcast *)appcast;
- (void)didFindValidUpdateWithAppcastItem:(SUAppcastItem *)appcastItem;
- (void)didNotFindUpdate;

@end

@interface SUAppcastDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(nullable id <SUAppcastDriverDelegate>)delegate;

- (void)loadAppcastFromURL:(NSURL *)appcastURL userAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates;

@property (nullable, nonatomic, readonly) SUAppcastItem *nonDeltaUpdateItem;

@end

NS_ASSUME_NONNULL_END
