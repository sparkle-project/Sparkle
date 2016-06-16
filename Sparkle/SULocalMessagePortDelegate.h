//
//  SULocalMessagePortDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SULocalMessagePortDelegate <NSObject>

// Note: this method may not be called on the main thread
// Due to XPC/asynchronous reasons, this cannot return any reply data back
- (void)localMessagePortReceivedMessageWithIdentifier:(int32_t)identifier data:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
