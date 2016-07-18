//
//  SUAuthorizationReply.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, SUAuthorizationReply)
{
    SUAuthorizationReplySuccess = 0,
    SUAuthorizationReplyCancelled = 1,
    SUAuthorizationReplyFailure = 2
};
