//
//  SUUnarchiver.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUnarchiver;
@protocol SUUnarchiverDelegate;

@interface SUUnarchiver : NSObject

+ (nullable id <SUUnarchiver>)unarchiverForPath:(NSString *)path updatingHostBundlePath:(NSString *)hostPath decryptionPassword:(nullable NSString *)decryptionPassword delegate:(nullable id <SUUnarchiverDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
