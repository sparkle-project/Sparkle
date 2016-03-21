//
//  SUInstallUpdateViewController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallUpdateViewController.h"
#import "SUAppcastItem.h"

@interface SUInstallUpdateViewController ()

@property (nonatomic) IBOutlet NSButton *skipUpdatesButton;
@property (nonatomic) IBOutlet NSTextView *textView;
@property (nonatomic, readonly) SUAppcastItem *appcastItem;
@property (nonatomic, copy) void (^reply)(SUUpdateAlertChoice);
@property (nonatomic, readonly) BOOL alreadyDownloaded;

@end

@implementation SUInstallUpdateViewController

@synthesize skipUpdatesButton = _skipUpdatesButton;
@synthesize textView = _textView;
@synthesize appcastItem = _appcastItem;
@synthesize reply = _reply;
@synthesize alreadyDownloaded = _alreadyDownloaded;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem alreadyDownloaded:(BOOL)alreadyDownloaded reply:(void (^)(SUUpdateAlertChoice))reply
{
    self = [super initWithNibName:@"SUInstallUpdateViewController" bundle:nil];
    if (self != nil) {
        _appcastItem = appcastItem;
        _alreadyDownloaded = alreadyDownloaded;
        self.reply = reply;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.skipUpdatesButton.enabled = !self.alreadyDownloaded;
    
    [[self.textView enclosingScrollView] setDrawsBackground:NO];
    [self.textView setDrawsBackground:NO];
    
    NSString *descriptionHTML = self.appcastItem.itemDescription;
    NSData *htmlData = [descriptionHTML dataUsingEncoding:NSUTF8StringEncoding];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:htmlData documentAttributes:NULL];
    [self.textView.textStorage setAttributedString:attributedString];
}

- (IBAction)installUpdate:(id)__unused sender
{
    if (self.reply != nil) {
        self.reply(SUInstallUpdateChoice);
        self.reply = nil;
    }
}

- (IBAction)installUpdateLater:(id)__unused sender
{
    if (self.reply != nil) {
        self.reply(SUInstallLaterChoice);
        self.reply = nil;
    }
}

- (IBAction)skipUpdate:(id)__unused sender
{
    if (self.reply != nil) {
        self.reply(SUSkipThisVersionChoice);
        self.reply = nil;
    }
}

@end
