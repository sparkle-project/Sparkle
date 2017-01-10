//
//  SUTouchBarProvider.m
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUTouchBarProvider.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101202

@interface SUTouchBarProvider() <NSTouchBarDelegate>

@property (copy) NSString* indentifier;
@property NSMutableArray<NSTouchBarItem*> *touchBarItems;

@end

@implementation SUTouchBarProvider

@synthesize indentifier;
@synthesize touchBarItems;
@synthesize touchBar;

-(instancetype)initWithIdentifier:(NSString *)anIdentifier
{
    if (!(self = [super init]))
        return self;
    
    indentifier = [NSString stringWithFormat:@"%@.%@", [NSBundle mainBundle].bundleIdentifier, anIdentifier];
    touchBarItems = [NSMutableArray arrayWithCapacity:6];
    
    touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[indentifier,];
    touchBar.principalItemIdentifier = indentifier;
    touchBar.delegate = self;
    
    return self;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:self.indentifier])
        return [NSGroupTouchBarItem groupItemWithIdentifier:self.indentifier items:self.touchBarItems];
    return nil;
}

-(NSButton *)addButtonWithButton:(NSButton *)button isDefault:(BOOL)isDefault
{
    NSString *itemId = [self.indentifier stringByAppendingFormat:@".button-%lu", self.touchBarItems.count];
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:itemId];

    NSButton *buttonCopy = [NSButton buttonWithTitle:button.title target:button.target action:button.action];
    buttonCopy.tag = button.tag;
    if (isDefault) {
        buttonCopy.keyEquivalent = @"\r";
    }
    
    [buttonCopy bind:@"title" toObject:button withKeyPath:@"title" options:nil];
    [buttonCopy bind:@"enabled" toObject:button withKeyPath:@"enabled" options:nil];

    item.view = buttonCopy;
    [self.touchBarItems addObject:item];
    return buttonCopy;
}

-(void)addSpace
{
    NSTouchBarItem *item = [[NSTouchBarItem alloc] initWithIdentifier:NSTouchBarItemIdentifierFixedSpaceLarge];
    [self.touchBarItems addObject:item];
}

@end

#else

@implementation SUTouchBarProvider

@synthesize touchBar;

-(instancetype)initWithIdentifier:(NSString *)identifier {
    return nil;
}

-(NSButton *)addButtonWithButton:(NSButton *)button {
    return nil;
}

-(void)addSpace {
}

@end

#endif
