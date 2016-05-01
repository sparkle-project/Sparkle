//
//  SUCommandLineDriver.h
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUCommandLineDriver : NSObject

- (instancetype)initWithUpdateBundlePath:(const char *)updateBundlePath relaunchBundlePath:(const char *)relaunchBundlePath;

- (void)run;

@end

NS_ASSUME_NONNULL_END
