//
//  SUInstallUpdateViewController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUStatusCompletionResults.h"

@class SUAppcastItem;

@interface SUInstallUpdateViewController : NSViewController

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem skippable:(BOOL)skippable reply:(void (^)(SUUpdateAlertChoice))reply;

@end
