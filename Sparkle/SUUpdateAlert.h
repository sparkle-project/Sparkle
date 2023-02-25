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
SPU_OBJC_DIRECT_MEMBERS @interface SUUpdateAlert : NSWindowController

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state host:(SUHost *)aHost versionDisplayer:(id<SUVersionDisplay>)versionDisplayer completionBlock:(void (^)(SPUUserUpdateChoice, NSRect, BOOL))completionBlock didBecomeKeyBlock:(void (^)(void))didBecomeKeyBlock;

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData;
- (void)showReleaseNotesFailedToDownload;

- (void)setInstallButtonFocus:(BOOL)focus;

@end

#endif

#endif
