//
//  SUURLDownload.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// From the completion block, either data or error can be nil, but not both
// The completion block returns on the main queue
void SUDownloadURLWithRequest(NSURLRequest * request, void (^completionBlock)(NSData * _Nullable data, NSError * _Nullable error));

NS_ASSUME_NONNULL_END
