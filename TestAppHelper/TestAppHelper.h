//
//  TestAppHelper.h
//  TestAppHelper
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TestAppHelperProtocol.h"

@protocol SPUUserDriver;

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface TestAppHelper : NSObject <TestAppHelperProtocol>

@end
