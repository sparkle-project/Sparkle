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

@interface SUUnarchiver : NSObject

@property (copy, readonly) NSString *archivePath;
@property (copy, readonly) NSString *_Nullable updateHostBundlePath;
@property (copy, readonly) NSString *_Nullable decryptionPassword;

+ (nullable SUUnarchiver *)unarchiverForPath:(NSString *)path updatingHostBundlePath:(nullable NSString *)host withPassword:(nullable NSString *)decryptionPassword;

+ (BOOL)unsafeIfArchiveIsNotValidated;

- (void)unarchiveWithCompletionBlock:(void (^)(NSError *_Nullable))completion progressBlock:(void (^_Nullable)(double progress))progress;

@end

NS_ASSUME_NONNULL_END
#endif
