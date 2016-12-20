//
//  SUUnarchiver.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUNARCHIVER_H
#define SUUNARCHIVER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;
@protocol SUUnarchiverDelegate;

@interface SUUnarchiver : NSObject

@property (copy, readonly) NSString *archivePath;
@property (copy, readonly) NSString *_Nullable updateHostBundlePath;
@property (copy, readonly) NSString *_Nullable decryptionPassword;
@property (weak) _Nullable id<SUUnarchiverDelegate> delegate;

+ (nullable SUUnarchiver *)unarchiverForPath:(NSString *)path updatingHostBundlePath:(nullable NSString *)host withPassword:(nullable NSString *)decryptionPassword;

+ (BOOL)unsafeIfArchiveIsNotValidated;

- (void)start;

@end

@protocol SUUnarchiverDelegate <NSObject>
- (void)unarchiverDidFinish:(SUUnarchiver *)unarchiver;
- (void)unarchiverDidFail:(SUUnarchiver *)unarchiver;
@optional
- (void)unarchiver:(SUUnarchiver *)unarchiver extractedProgress:(double)progress;
@end

NS_ASSUME_NONNULL_END
#endif
