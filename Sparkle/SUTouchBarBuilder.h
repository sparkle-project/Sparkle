//
//  SUTouchBarBuilder.h
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class NSTouchBar;

NS_ASSUME_NONNULL_BEGIN

@interface SUTouchBarBuilder : NSObject

@property (strong, readonly) NSTouchBar *touchBar;

- (instancetype)initWithIdentifier:(NSString *)identifier;
- (NSButton *)addButtonUsingButton:(NSButton *)button isDefault:(BOOL)isDefault;
- (void)addSpace;

@end

NS_ASSUME_NONNULL_END
