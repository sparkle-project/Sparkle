//
//  SPUExtractAppcast.m
//  Sparkle
//
//  Created on 12/25/25.
//  Copyright © 2025 Sparkle Project. All rights reserved.
//

#import "SPUExtractAppcast.h"

NSData *SPUExtractAppcastContent(NSData *appcastData, NSString * _Nullable __autoreleasing * _Nullable outEdSignatureBase64, uint64_t * _Nullable outContentLength)
{
    static char feedSigningPrefix[] = "<!-- sparkle-signatures:\n";
    static char feedSigningSuffix[] = "-->";
    
    NSUInteger appcastDataLength = appcastData.length;
    
    NSRange prefixRange = [appcastData rangeOfData:[NSData dataWithBytesNoCopy:feedSigningPrefix length:sizeof(feedSigningPrefix) - 1 freeWhenDone:NO] options:NSDataSearchBackwards range:NSMakeRange(0, appcastDataLength)];
    
    if (prefixRange.location == NSNotFound) {
        return appcastData;
    }
    
    NSData *contentFeedData = [appcastData subdataWithRange:NSMakeRange(0, prefixRange.location)];
    
    NSRange suffixRange = [appcastData rangeOfData:[NSData dataWithBytesNoCopy:feedSigningSuffix length:sizeof(feedSigningSuffix) - 1 freeWhenDone:NO] options:0 range:NSMakeRange(NSMaxRange(prefixRange), appcastDataLength - NSMaxRange(prefixRange))];
    
    if (suffixRange.location == NSNotFound) {
        return appcastData;
    }
    
    NSData *signingBlockData = [appcastData subdataWithRange:NSMakeRange(NSMaxRange(prefixRange), suffixRange.location - NSMaxRange(prefixRange))];
    
    NSString *signingBlockString = [[NSString alloc] initWithData:signingBlockData encoding:NSUTF8StringEncoding];
    if (signingBlockString == nil) {
        return appcastData;
    }
    
    __block NSString *edSignatureBase64 = nil;
    __block uint64_t contentLength = 0;
    static NSString *edSignatureKey = @"edSignature:";
    static NSString *lengthKey = @"length:";
    [signingBlockString enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull __unused stop) {
        if ([line hasPrefix:edSignatureKey]) {
            edSignatureBase64 = [[line substringFromIndex:edSignatureKey.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        } else if ([line hasPrefix:lengthKey]) {
            contentLength = (uint64_t)[[[line substringFromIndex:lengthKey.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] longLongValue];
        }
    }];
    
    if (outEdSignatureBase64 != nil) {
        *outEdSignatureBase64 = [edSignatureBase64 copy];
    }
    
    if (outContentLength != NULL) {
        *outContentLength = contentLength;
    }
    
    return contentFeedData;
}
