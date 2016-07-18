//
//  SUUnarchiverProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/26/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUnarchiverProtocol <NSObject>

+ (BOOL)canUnarchivePath:(NSString *)path;

- (void)start;

- (NSString *)description;

@end

@protocol SUUnarchiverDelegate <NSObject>

- (void)unarchiverDidFinish;

- (void)unarchiverDidFail;

@optional
- (void)unarchiverExtractedProgress:(double)progress;

@end

NS_ASSUME_NONNULL_END
