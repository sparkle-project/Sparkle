//
//  SUWebViewCommon.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/31/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUWebViewCommon.h"


#include "AppKitPrevention.h"

BOOL SUWebViewIsSafeURL(NSURL *url, BOOL *isAboutBlankURL)
{
    NSString *scheme = url.scheme;
    BOOL isAboutBlank = [url.absoluteString isEqualToString:@"about:blank"] || [url.absoluteString isEqualToString:@"about:srcdoc"];
    BOOL whitelistedSafe = isAboutBlank || [@[@"http", @"https", @"macappstore", @"macappstores", @"itms-apps", @"itms-appss"] containsObject:scheme];
    
    *isAboutBlankURL = isAboutBlank;
    
    return whitelistedSafe;
}

#endif
