//
//  SUCommandLineUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Sparkle/Sparkle.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUCommandLineUserDriver : NSObject <SUUserDriver>

- (instancetype)initWithApplicationBundle:(NSBundle *)applicationBundle deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose;

@end

NS_ASSUME_NONNULL_END
