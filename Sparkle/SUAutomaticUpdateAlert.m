//
//  SUAutomaticUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateAlert.h"
#import "SULocalizations.h"
#import "SUAppcastItem.h"
#import "SUApplicationInfo.h"
#import "SUHost.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUAutomaticUpdateAlertTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUAutomaticUpdateAlert";

@interface SUAutomaticUpdateAlert () <NSTouchBarDelegate>
@property (strong) void(^completionBlock)(SUAutomaticInstallationChoice);
@property (strong) SUAppcastItem *updateItem;
@property (strong) SUHost *host;

@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSButton *laterButton;
@property (weak) IBOutlet NSButton *installButton;
@end

@implementation SUAutomaticUpdateAlert
@synthesize host;
@synthesize updateItem;
@synthesize completionBlock;
@synthesize skipButton;
@synthesize laterButton;
@synthesize installButton;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost completionBlock:(void (^)(SUAutomaticInstallationChoice))block
{
    self = [super initWithWindowNibName:@"SUAutomaticUpdateAlert"];
    if (self) {
        self.updateItem = item;
        self.completionBlock = block;
        self.host = aHost;
        [self setShouldCascadeWindows:NO];

        [[self window] center];
    }
    return self;
}

- (NSString *__nonnull)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (IBAction)installNow:(id)__unused sender
{
    [self close];
    self.completionBlock(SUInstallNowChoice);
    self.completionBlock = nil;
}

- (IBAction)installLater:(id)__unused sender
{
    [self close];
    self.completionBlock(SUInstallLaterChoice);
    self.completionBlock = nil;
}

- (IBAction)doNotInstall:(id)__unused sender
{
    [self close];
    self.completionBlock(SUDoNotInstallChoice);
    self.completionBlock = nil;
}

- (void)windowDidLoad
{
    if ([self.updateItem isCriticalUpdate]) {
        self.skipButton.enabled = NO;
    }
}


- (NSImage *__nonnull)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:self.host];
}

- (NSString *__nonnull)titleText
{
    if ([self.updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"An important update to %@ is ready to install", nil), [self.host name]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is ready to install!", nil), [self.host name]];
    }
}

- (NSString *)descriptionText
{
    if ([self.updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", nil), [self.host name], [self.updateItem displayVersionString]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", nil), [self.host name], [self.updateItem displayVersionString]];
    }
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSClassFromString(@"NSTouchBar") alloc] init];
    touchBar.defaultItemIdentifiers = @[SUAutomaticUpdateAlertTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUAutomaticUpdateAlertTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUAutomaticUpdateAlertTouchBarIndentifier]) {
        NSCustomTouchBarItem* item = [(NSCustomTouchBarItem *)[NSClassFromString(@"NSCustomTouchBarItem") alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[self.installButton, self.laterButton, self.skipButton]];
        return item;
    }
    return nil;
}

@end
