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
#import "SPUStatusCompletionResults.h"

@protocol SUUpdateAlertDelegate;

@class SUAppcastItem, SPUDownloadData, SUHost;
@interface SUUpdateAlert : NSWindowController

@property (nonatomic, weak, readonly) id <SUVersionDisplay> versionDisplayer;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item alreadyDownloaded:(BOOL)alreadyDownloaded host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer completionBlock:(void (^)(SPUUpdateAlertChoice))block;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer resumableCompletionBlock:(void (^)(SPUInstallUpdateStatus))block;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer informationalCompletionBlock:(void (^)(SPUInformationalUpdateAlertChoice))block;

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData;
- (void)showReleaseNotesFailedToDownload;

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;
- (void)disableKeyboardShortcutForInstallButton;

@end

#endif
