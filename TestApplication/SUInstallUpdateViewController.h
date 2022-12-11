//
//  SUInstallUpdateViewController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

__attribute__((objc_direct_members)) @interface SUInstallUpdateViewController : NSViewController

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SPUUserUpdateChoice))reply;

- (void)showReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData;

@end
