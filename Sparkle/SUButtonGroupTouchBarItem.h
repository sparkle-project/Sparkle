//
//  SUButtonGroupTouchBarItem.h
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class NSTouchBar;
@class NSTouchBarItem;

NS_ASSUME_NONNULL_BEGIN

@interface SUButtonGroupTouchBarItem : NSTouchBarItem

+ (NSTouchBarItem *)itemWithIndentifier:(NSString *)indentifier usingButtons:(NSArray<NSButton *> *)buttons;

@end

NS_ASSUME_NONNULL_END
