//
//  SUPKGUnarchiver
//  Sparkle
//
//  Created by Thomas Schmitt
//  Copyright 2013-2019 Thomas Schmitt. All rights reserved.
//

#ifndef SUPKGUNARCHIVER_H
#define SUPKGUNARCHIVER_H

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUPKGUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithArchivePath:(NSString *)archivePath;

@end

NS_ASSUME_NONNULL_END

#endif
