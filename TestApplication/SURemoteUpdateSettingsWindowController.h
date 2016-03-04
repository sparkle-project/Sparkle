//
//  SURemoteUpdateSettingsWindowController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

@protocol SUStandardUserDriverDelegate;

@interface SURemoteUpdateSettingsWindowController : NSWindowController <SUStandardUserDriverDelegate>

// If you invoke this, it's assumed you used its return value and returned from
// NSApplicationDelegate's -applicationShouldTerminate:
- (NSApplicationTerminateReply)sendTerminationSignal;

@end
