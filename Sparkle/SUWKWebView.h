//
//  SUWKWebView.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUWebView.h"

NS_ASSUME_NONNULL_BEGIN

// Only use this class on macOS 10.11 or later (see implementation for rationale)
@interface SUWKWebView : NSObject <SUWebView>

- (instancetype)initWithColorStyleSheetLocation:(NSURL *)colorStyleSheetLocation fontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize javaScriptEnabled:(BOOL)javaScriptEnabled;

@end

NS_ASSUME_NONNULL_END
