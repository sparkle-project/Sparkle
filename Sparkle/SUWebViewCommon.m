//
//  SUWebViewCommon.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/31/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#import "SUWebViewCommon.h"

BOOL SUWebViewIsSafeURL(NSURL *url, BOOL *isAboutBlankURL)
{
    NSString *scheme = url.scheme;
    BOOL isAboutBlank = [url.absoluteString isEqualToString:@"about:blank"];
    BOOL whitelistedSafe = isAboutBlank || [@[@"http", @"https", @"macappstore", @"macappstores", @"itms-apps", @"itms-appss"] containsObject:scheme];
    
    *isAboutBlankURL = isAboutBlank;
    
    return whitelistedSafe;
}
