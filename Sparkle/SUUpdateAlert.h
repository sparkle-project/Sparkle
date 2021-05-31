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
#import "SPUUserUpdateChoice.h"

@protocol SUUpdateAlertDelegate;

@class SUAppcastItem, SPUDownloadData, SUHost, SPUUpdateState;
@interface SUUpdateAlert : NSWindowController

@property (nonatomic, weak, readonly) id <SUVersionDisplay> versionDisplayer;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item state:(SPUUpdateState *)state host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer completionBlock:(void (^)(SPUUserUpdateChoice))block;

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData;
- (void)showReleaseNotesFailedToDownload;

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;

- (void)setInstallButtonFocus:(BOOL)focus;

@end

#endif
