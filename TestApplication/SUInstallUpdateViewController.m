//
//  SUInstallUpdateViewController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallUpdateViewController.h"

@interface SUInstallUpdateViewController ()

@property (nonatomic) IBOutlet NSButton *skipUpdatesButton;
@property (nonatomic) IBOutlet NSTextView *textView;
@property (nonatomic, readonly) SUAppcastItem *appcastItem;
@property (nonatomic, nullable) NSAttributedString *preloadedReleaseNotes;
@property (nonatomic, copy) void (^reply)(SPUUserUpdateChoice);

@end

@implementation SUInstallUpdateViewController

@synthesize skipUpdatesButton = _skipUpdatesButton;
@synthesize textView = _textView;
@synthesize preloadedReleaseNotes = _preloadedReleaseNotes;
@synthesize appcastItem = _appcastItem;
@synthesize reply = _reply;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SPUUserUpdateChoice))reply
{
    self = [super initWithNibName:@"SUInstallUpdateViewController" bundle:nil];
    if (self != nil) {
        _appcastItem = appcastItem;
        self.reply = reply;
    } else {
        assert(false);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[self.textView enclosingScrollView] setDrawsBackground:NO];
    [self.textView setDrawsBackground:NO];
    
    if (self.preloadedReleaseNotes != nil) {
        [self displayReleaseNotes:self.preloadedReleaseNotes];
        self.preloadedReleaseNotes = nil;
    } else if (self.appcastItem.releaseNotesURL == nil) {
        NSString *descriptionHTML = self.appcastItem.itemDescription;
        if (descriptionHTML != nil) {
            NSData *htmlData = [descriptionHTML dataUsingEncoding:NSUTF8StringEncoding];
            NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:htmlData documentAttributes:NULL];
            [self displayReleaseNotes:attributedString];
        }
    }
}

- (void)displayReleaseNotes:(NSAttributedString *)releaseNotes
{
    if (self.textView == nil) {
        self.preloadedReleaseNotes = releaseNotes;
    } else {
        [self.textView.textStorage setAttributedString:releaseNotes];
    }
}

- (void)displayHTMLReleaseNotes:(NSData *)releaseNotes
{
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:releaseNotes documentAttributes:NULL];
    [self displayReleaseNotes:attributedString];
}

- (void)displayPlainTextReleaseNotes:(NSData *)releaseNotes encoding:(NSStringEncoding)encoding
{
    NSString *string = [[NSString alloc] initWithData:releaseNotes encoding:encoding];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:nil];
    [self displayReleaseNotes:attributedString];
}

- (void)showReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    // Partially copied from SPUCommandLineUserDriver
    // Not all user drivers need this kind of implementation (eg: see SPUStandardUserDriver)
    // Also I'm not extremely confident about the correctness of this code so I don't want to export it publicly
    if (downloadData.MIMEType != nil && [downloadData.MIMEType isEqualToString:@"text/plain"]) {
        NSStringEncoding encoding;
        if (downloadData.textEncodingName == nil) {
            encoding = NSUTF8StringEncoding;
        } else {
            CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)downloadData.textEncodingName);
            if (cfEncoding != kCFStringEncodingInvalidId) {
                encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
            } else {
                encoding = NSUTF8StringEncoding;
            }
        }
        [self displayPlainTextReleaseNotes:downloadData.data encoding:encoding];
    } else {
        [self displayHTMLReleaseNotes:downloadData.data];
    }
}

- (IBAction)installUpdate:(id)__unused sender
{
    if (self.reply != nil) {
        self.reply(SPUUserUpdateChoiceInstall);
        self.reply = nil;
    }
}

- (IBAction)installUpdateLater:(id)__unused sender
{
    if (self.reply != nil) {
        self.reply(SPUUserUpdateChoiceDismiss);
        self.reply = nil;
    }
}

- (IBAction)skipUpdate:(id)__unused sender
{
    if (self.reply != nil) {
        self.reply(SPUUserUpdateChoiceSkip);
        self.reply = nil;
    }
}

@end
