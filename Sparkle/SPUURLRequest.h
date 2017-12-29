//
//  SPUURLRequest.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/19/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A class that wraps NSURLRequest and implements NSSecureCoding
// This class exists because NSURLRequest did not support NSSecureCoding in macOS 10.8
// I have not verified if NSURLRequest in 10.9 implements NSSecureCoding or not
@interface SPUURLRequest : NSObject <NSSecureCoding>

// Creates a new URL request
// Only these properties are currently tracked:
// * URL
// * Cache policy
// * Timeout interval
// * HTTP header fields
// * networkServiceType
+ (instancetype)URLRequestWithRequest:(NSURLRequest *)request;

@property (nonatomic, readonly) NSURLRequest *request;

@end

NS_ASSUME_NONNULL_END
