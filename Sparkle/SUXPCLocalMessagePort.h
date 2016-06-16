//
//  SUXPCLocalMessagePort.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SULocalMessagePortProtocol.h"
#import "SULocalMessagePortDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUXPCLocalMessagePort : NSObject <SULocalMessagePortProtocol>

// Due to XPC reasons, this delegate is strongly referenced. Make sure to -invalidate when done with this instance.
- (instancetype)initWithDelegate:(id<SULocalMessagePortDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
