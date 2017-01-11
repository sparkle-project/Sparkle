//
//  SUButtonGroupTouchBarItem.m
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUButtonGroupTouchBarItem.h"
#import "SUConstants.h"

@implementation SUButtonGroupTouchBarItem

+ (NSTouchBarItem *)itemWithIndentifier:(NSString *)indentifier usingButtons:(NSArray<NSButton *> *)buttons
{
    NSMutableArray<NSTouchBarItem*> *touchBarItems = [NSMutableArray arrayWithCapacity:buttons.count + 1];
    
    for (NSUInteger i = 0; i < buttons.count; i++) {
        if (i == 2) {
            NSTouchBarItem *item = [[NSTouchBarItem alloc] initWithIdentifier:NSTouchBarItemIdentifierFixedSpaceLarge];
            [touchBarItems insertObject:item atIndex:0];
        }
        NSButton *button = buttons[i];
        NSButton *buttonCopy = [NSButton buttonWithTitle:button.title target:button.target action:button.action];
        buttonCopy.tag = button.tag;
        
        if (i == 0) {
            buttonCopy.keyEquivalent = @"\r";
        }
        
        [buttonCopy bind:@"title" toObject:button withKeyPath:@"title" options:nil];
        [buttonCopy bind:@"enabled" toObject:button withKeyPath:@"enabled" options:nil];
        
        NSString *itemId = [indentifier stringByAppendingFormat:@".button-%lu", i];
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:itemId];
        item.view = buttonCopy;
        [touchBarItems insertObject:item atIndex:0];
    }
    
    return [NSGroupTouchBarItem groupItemWithIdentifier:indentifier items:touchBarItems];
}

@end

