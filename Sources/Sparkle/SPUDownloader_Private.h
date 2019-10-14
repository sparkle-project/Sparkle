//
//  SPUDownloader_Private.h
//  Sparkle
//
//  Created by Deadpikle on 12/20/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#ifndef SPUDownloader_Private_h
#define SPUDownloader_Private_h

#import "SPUDownloaderDelegate.h"

typedef NS_ENUM(NSUInteger, SPUDownloadMode)
{
    SPUDownloadModePersistent,
    SPUDownloadModeTemporary
};

static NSString *SUDownloadingReason = @"Downloading update related file";

@interface SPUDownloader ()

// Delegate is intentionally strongly referenced; see header
@property (nonatomic) id <SPUDownloaderDelegate> delegate;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *desiredFilename;
@property (nonatomic, copy) NSString *downloadFilename;
@property (nonatomic) BOOL disabledAutomaticTermination;
@property (nonatomic) SPUDownloadMode mode;
@property (nonatomic) BOOL receivedExpectedBytes;

// returns temp directory location if successful; if not successful,
// returns nil after sending error message to client and canceling download
-(NSString*)getAndCleanTempDirectory;

-(void)downloadDidFinishWithData:(SPUDownloadData*)data;

@end

#endif /* SPUDownloader_Private_h */
