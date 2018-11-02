//
//  SUInstallUpdateViewController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

@interface SUInstallUpdateViewController : NSViewController

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem skippable:(BOOL)skippable reply:(void (^)(SPUUpdateAlertChoice))reply;

- (void)showReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData;

@end
