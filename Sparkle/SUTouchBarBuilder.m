//
//  SUTouchBarBuilder.m
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUTouchBarBuilder.h"
#import "SUConstants.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101202

@interface SUTouchBarBuilder() <NSTouchBarDelegate>

@property (nonatomic, copy) NSString* indentifier;
@property (nonatomic) NSMutableArray<NSTouchBarItem*> *touchBarItems;

@end

@implementation SUTouchBarBuilder

@synthesize indentifier = _indentifier;
@synthesize touchBarItems = _touchBarItems;
@synthesize touchBar = _touchBar;

- (instancetype)initWithIdentifier:(NSString *)anIdentifier
{
    if (!(self = [super init]))
        return self;
    
    _indentifier = [NSString stringWithFormat:@"%@.%@", SUBundleIdentifier, anIdentifier];
    _touchBarItems = [NSMutableArray array];
    
    _touchBar = [[NSTouchBar alloc] init];
    _touchBar.defaultItemIdentifiers = @[_indentifier,];
    _touchBar.principalItemIdentifier = _indentifier;
    _touchBar.delegate = self;
    
    return self;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:self.indentifier])
        return [NSGroupTouchBarItem groupItemWithIdentifier:self.indentifier items:self.touchBarItems];
    return nil;
}

- (NSButton *)addButtonUsingButton:(NSButton *)button isDefault:(BOOL)isDefault
{
    NSString *itemId = [self.indentifier stringByAppendingFormat:@".button-%lu", self.touchBarItems.count];
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:itemId];

    NSButton *buttonCopy = [NSButton buttonWithTitle:button.title target:button.target action:button.action];
    buttonCopy.tag = button.tag;
    
    // A modal NSWindow may empty its default button's keyEquivalent when it shows.
    // We have to set the default button explicitly.
    if (isDefault) {
        buttonCopy.keyEquivalent = @"\r";
    }
    
    [buttonCopy bind:@"title" toObject:button withKeyPath:@"title" options:nil];
    [buttonCopy bind:@"enabled" toObject:button withKeyPath:@"enabled" options:nil];

    item.view = buttonCopy;
    [self.touchBarItems addObject:item];
    return buttonCopy;
}

- (void)addSpace
{
    NSTouchBarItem *item = [[NSTouchBarItem alloc] initWithIdentifier:NSTouchBarItemIdentifierFixedSpaceLarge];
    [self.touchBarItems addObject:item];
}

@end

#else

@implementation SUTouchBarBuilder

@synthesize touchBar;

-(instancetype)initWithIdentifier:(NSString *)identifier {
    return nil;
}

-(NSButton *)addButtonUsingButton:(NSButton *)button isDefault:(BOOL)isDefault{
    return nil;
}

-(void)addSpace {
}

@end

#endif
