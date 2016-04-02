//
//  SUAppcastDownloader.h
//  AppcastDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUAppcastDownloaderProtocol.h"

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface SUAppcastDownloader : NSObject <SUAppcastDownloaderProtocol>
@end
