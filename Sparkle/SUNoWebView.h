//
//  SUNoWebView.h
//  Sparkle
//
//  Created on 9/11/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import <Foundation/Foundation.h>

#import "SUWebView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUNoWebView : NSObject <SUWebView>

- (instancetype)initWithFontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize;

@end

NS_ASSUME_NONNULL_END

#endif
