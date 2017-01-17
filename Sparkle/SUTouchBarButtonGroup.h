//
//  SUTouchBarButtonGroup.h
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUTouchBarButtonGroup : NSViewController

@property (nonatomic, readonly, copy) NSArray<NSButton *> *buttons;

- (instancetype)initByReferencingButtons:(NSArray<NSButton *> *)buttons;

@end

NS_ASSUME_NONNULL_END
