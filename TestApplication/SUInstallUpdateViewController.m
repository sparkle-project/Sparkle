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

@property (nonatomic) IBOutlet NSTextView *textView;
@property (nonatomic, readonly) SUAppcastItem *appcastItem;
@property (nonatomic, copy) void (^reply)(SUUpdateAlertChoice);

@end

@implementation SUInstallUpdateViewController

@synthesize textView = _textView;
@synthesize appcastItem = _appcastItem;
@synthesize reply = _reply;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUUpdateAlertChoice))reply
{
    self = [super initWithNibName:@"SUInstallUpdateViewController" bundle:nil];
    if (self != nil) {
        _appcastItem = appcastItem;
        self.reply = reply;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
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
