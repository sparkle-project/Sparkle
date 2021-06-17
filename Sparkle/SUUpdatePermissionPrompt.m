//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUUpdatePermissionPrompt.h"
#import "SPUUpdatePermissionRequest.h"
#import "SUUpdatePermissionResponse.h"
#import "SULocalizations.h"

#import "SUHost.h"
#import "SUConstants.h"
#import "SUApplicationInfo.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUUpdatePermissionPromptTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdatePermissionPrompt";

@interface SUUpdatePermissionPrompt () <NSTouchBarDelegate>

@property (nonatomic) BOOL shouldSendProfile;

@property (nonatomic) SUHost *host;
@property (nonatomic) NSArray *systemProfileInformationArray;

@property (nonatomic) IBOutlet NSStackView *stackView;
@property (nonatomic) IBOutlet NSView *promptView;
@property (nonatomic) IBOutlet NSView *moreInfoView;
@property (nonatomic) IBOutlet NSView *placeholderView;
@property (nonatomic) IBOutlet NSView *responseView;
@property (nonatomic) IBOutlet NSView *infoChoiceView;

@property (nonatomic) IBOutlet NSButton *cancelButton;
@property (nonatomic) IBOutlet NSButton *checkButton;
@property (nonatomic) IBOutlet NSButton *anonymousInfoDisclosureButton;

@property (nonatomic) IBOutlet NSLayoutConstraint *placeholderHeightLayoutConstraint;

@property (nonatomic, readonly) void (^reply)(SUUpdatePermissionResponse *);

@end

@implementation SUUpdatePermissionPrompt

@synthesize reply = _reply;
@synthesize shouldSendProfile = _shouldSendProfile;
@synthesize host = _host;
@synthesize systemProfileInformationArray = _systemProfileInformationArray;
@synthesize stackView = _stackView;
@synthesize promptView = _promtView;
@synthesize moreInfoView = _moreInfoView;
@synthesize placeholderView = _placeholderView;
@synthesize responseView = _responseView;
@synthesize infoChoiceView = _infoChoiceView;
@synthesize cancelButton = _cancelButton;
@synthesize checkButton = _checkButton;
@synthesize anonymousInfoDisclosureButton = _anonymousInfoDisclosureButton;
@synthesize placeholderHeightLayoutConstraint = _placeholderHeightLayoutConstraint;

- (instancetype)initPromptWithHost:(SUHost *)theHost request:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    self = [super initWithWindowNibName:@"SUUpdatePermissionPrompt"];
    if (self)
    {
        _reply = reply;
        _host = theHost;
        _shouldSendProfile = [self shouldAskAboutProfile];
        _systemProfileInformationArray = request.systemProfile;
        [self setShouldCascadeWindows:NO];
    } else {
        assert(false);
    }
    return self;
}

- (BOOL)shouldAskAboutProfile
{
    return [(NSNumber *)[self.host objectForInfoDictionaryKey:SUEnableSystemProfilingKey] boolValue];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)windowDidLoad
{
    [self.window center];
    
    self.infoChoiceView.hidden = ![self shouldAskAboutProfile];
    
    [self.stackView addArrangedSubview:self.promptView];
    [self.stackView addArrangedSubview:self.infoChoiceView];
    [self.stackView addArrangedSubview:self.placeholderView];
    [self.stackView addArrangedSubview:self.moreInfoView];
    [self.stackView addArrangedSubview:self.responseView];
}

- (BOOL)tableView:(NSTableView *) __unused tableView shouldSelectRow:(NSInteger) __unused row { return NO; }


- (NSImage *)icon
{
    return [SUApplicationInfo bestIconForHost:self.host];
}

- (NSString *)promptDescription
{
    return [NSString stringWithFormat:SULocalizedString(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", nil), [self.host name]];
}

- (IBAction)toggleMoreInfo:(id)__unused sender
{
    // Use a placeholder view to unhide/hide before putting the more info view in place
    // This allows us to animate resizing the more info view in place more easily
    
    static const CGFloat TOGGLE_INFO_ANIMATION_DURATION = 0.2;
    
    BOOL disclosingInfo = (self.anonymousInfoDisclosureButton.state == NSControlStateValueOn);
    
    if (disclosingInfo) {
        self.placeholderHeightLayoutConstraint.constant = 0.0;
        self.placeholderView.hidden = NO;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = TOGGLE_INFO_ANIMATION_DURATION;
            
            self.placeholderHeightLayoutConstraint.animator.constant = self.moreInfoView.frame.size.height;
        } completionHandler:^{
            self.placeholderView.hidden = YES;
            self.moreInfoView.hidden = NO;
        }];
    } else {
        self.placeholderHeightLayoutConstraint.constant = self.moreInfoView.frame.size.height;
        self.moreInfoView.hidden = YES;
        self.placeholderView.hidden = NO;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = TOGGLE_INFO_ANIMATION_DURATION;
            
            self.placeholderHeightLayoutConstraint.animator.constant = 0.0;
        } completionHandler:^{
            self.placeholderView.hidden = YES;
        }];
    }
}

- (IBAction)finishPrompt:(NSButton *)sender
{
    SUUpdatePermissionResponse *response = [[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:([sender tag] == 1) sendSystemProfile:self.shouldSendProfile];
    self.reply(response);
    
    [self close];
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [(NSTouchBar *)[NSClassFromString(@"NSTouchBar") alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdatePermissionPromptTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUUpdatePermissionPromptTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier API_AVAILABLE(macos(10.12.2))
{
    if ([identifier isEqualToString:SUUpdatePermissionPromptTouchBarIndentifier]) {
        NSCustomTouchBarItem* item = [(NSCustomTouchBarItem *)[NSClassFromString(@"NSCustomTouchBarItem") alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[self.checkButton, self.cancelButton]];
        return item;
    }
    return nil;
}

@end

#endif
