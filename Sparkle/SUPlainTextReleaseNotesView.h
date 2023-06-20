//
//  SUPlainTextReleaseNotesView.h
//  Sparkle
//
//  Created on 9/11/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import <Foundation/Foundation.h>

#import "SUReleaseNotesView.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUPlainTextReleaseNotesView : NSObject <SUReleaseNotesView>

- (instancetype)initWithFontPointSize:(int)fontPointSize customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes;

@end

NS_ASSUME_NONNULL_END

#endif
