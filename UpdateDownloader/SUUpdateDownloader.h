//
//  SUUpdateDownloader.h
//  UpdateDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUpdateDownloaderProtocol.h"

@protocol SUDownloaderDelegate;

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface SUUpdateDownloader : NSObject <SUUpdateDownloaderProtocol>

- (instancetype)initWithDelegate:(id <SUDownloaderDelegate>)delegate;

@end
