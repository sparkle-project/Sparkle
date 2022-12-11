//
//  SUTouchBarButtonGroup.h
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUTouchBarButtonGroup : NSViewController

@property (nonatomic, readonly, copy) NSArray<NSButton *> *buttons;

- (instancetype)initByReferencingButtons:(NSArray<NSButton *> *)buttons __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END

#endif
