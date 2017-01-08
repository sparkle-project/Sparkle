//
//  SUTouchBar.h
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class NSTouchBar;

@interface SUTouchBar : NSTouchBar

-(instancetype)initWithIdentifier:(NSString *)identifier;
-(NSButton *)addButtonWithButton:(NSButton *)button;
-(void)addSpace;

@end
