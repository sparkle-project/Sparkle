//
//  SUPipedUnarchiver.h
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUPIPEDUNARCHIVER_H
#define SUPIPEDUNARCHIVER_H

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUPipedUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithArchivePath:(NSString *)archivePath __attribute__((objc_direct));

+ (BOOL)canUnarchivePath:(NSString *)path __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END

#endif
