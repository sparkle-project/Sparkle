//
//  SUUpdateAlert.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATEALERT_H
#define SUUPDATEALERT_H

#import <Cocoa/Cocoa.h>
#import "SUVersionDisplayProtocol.h"
#import "SUStatusCompletionResults.h"

@protocol SUUpdateAlertDelegate;

@class SUAppcastItem, SUHost;
@interface SUUpdateAlert : NSWindowController

@property (weak) id<SUVersionDisplay> versionDisplayer;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)host allowsAutomaticUpdates:(BOOL)allowsAutomaticUpdates completionBlock:(void(^)(SUUpdateAlertChoice))c;

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;

@end

#endif
