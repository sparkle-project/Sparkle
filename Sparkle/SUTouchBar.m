//
//  SUTouchBar.m
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUTouchBar.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101202

@interface SUTouchBar()

@property (copy) NSString* indentifier;
@property NSMutableArray<NSTouchBarItem*> *touchBarItems;

@end

@implementation SUTouchBar

@synthesize indentifier;
@synthesize touchBarItems;

-(instancetype)initWithIdentifier:(NSString *)anIdentifier
{
    if (!(self = [super init]))
        return self;
    
    self.indentifier = [NSString stringWithFormat:@"%@.%@", [NSBundle mainBundle].bundleIdentifier, anIdentifier];
    self.touchBarItems = [NSMutableArray arrayWithCapacity:6];
    
    self.defaultItemIdentifiers = @[self.indentifier,];
    self.principalItemIdentifier = self.indentifier;
    
    return self;
}

- (NSTouchBarItem *)itemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:self.indentifier])
        return [NSGroupTouchBarItem groupItemWithIdentifier:self.indentifier items:self.touchBarItems];
    return [super itemForIdentifier:identifier];
}

-(NSButton *)addButtonWithButton:(NSButton *)button
{
    NSString *itemId = [self.indentifier stringByAppendingFormat:@".button-%lu", self.touchBarItems.count];
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:itemId];

    NSButton *buttonCopy = [NSButton buttonWithTitle:button.title target:button.target action:button.action];
    buttonCopy.keyEquivalent = button.keyEquivalent;
    buttonCopy.tag = button.tag;

    item.view = buttonCopy;
    [self.touchBarItems addObject:item];
    return buttonCopy;
}

-(void)addSpace
{
    NSTouchBarItem *item = [super itemForIdentifier:NSTouchBarItemIdentifierFixedSpaceLarge];
    [self.touchBarItems addObject:item];
}

@end

#else

@interface NSTouchBar : NSObject

@end

@implementation NSTouchBar

@end

@implementation SUTouchBar

-(instancetype)initWithIdentifier:(NSString *)identifier {
    return nil;
}

-(NSButton *)addButtonWithButton:(NSButton *)button {
    return nil;
}

-(void)addSpace {
    return nil;
}

@end

#endif
