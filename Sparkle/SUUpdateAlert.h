//
//  SUUpdateAlert.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#ifndef SUUPDATEALERT_H
#define SUUPDATEALERT_H

#import <Cocoa/Cocoa.h>
#import "SUVersionDisplayProtocol.h"
#import "SPUUserUpdateState.h"

@protocol SUUpdateAlertDelegate;

@class SUAppcastItem, SPUDownloadData, SUHost;
@interface SUUpdateAlert : NSWindowController

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer completionBlock:(void (^)(SPUUserUpdateChoice, NSRect, BOOL))completionBlock didBecomeKeyBlock:(void (^)(void))didBecomeKeyBlock __attribute__((objc_direct));

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData __attribute__((objc_direct));
- (void)showReleaseNotesFailedToDownload __attribute__((objc_direct));

- (IBAction)installUpdate:sender;
- (IBAction)skipThisVersion:sender;
- (IBAction)remindMeLater:sender;

- (void)setInstallButtonFocus:(BOOL)focus __attribute__((objc_direct));

@end

#endif

#endif
