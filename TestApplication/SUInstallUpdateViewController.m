//
//  SUInstallUpdateViewController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallUpdateViewController.h"

@implementation SUInstallUpdateViewController
{
    void (^_reply)(SPUUserUpdateChoice);
    
    SUAppcastItem *_appcastItem;
    NSAttributedString *_preloadedReleaseNotes;
    
    IBOutlet NSTextView *_textView;
    IBOutlet NSButton *_skipUpdatesButton;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SPUUserUpdateChoice))reply
{
    self = [super initWithNibName:@"SUInstallUpdateViewController" bundle:nil];
    if (self != nil) {
        _appcastItem = appcastItem;
        _reply = [reply copy];
    } else {
        assert(false);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[_textView enclosingScrollView] setDrawsBackground:NO];
    [_textView setDrawsBackground:NO];
    
    if (_preloadedReleaseNotes != nil) {
        [self displayReleaseNotes:_preloadedReleaseNotes];
        _preloadedReleaseNotes = nil;
    } else if (_appcastItem.releaseNotesURL == nil) {
        NSString *descriptionHTML = _appcastItem.itemDescription;
        if (descriptionHTML != nil) {
            NSData *htmlData = [descriptionHTML dataUsingEncoding:NSUTF8StringEncoding];
            NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:htmlData documentAttributes:NULL];
            [self displayReleaseNotes:attributedString];
        }
    }
}

- (void)displayReleaseNotes:(NSAttributedString *)releaseNotes SPU_OBJC_DIRECT
{
    if (_textView == nil) {
        _preloadedReleaseNotes = releaseNotes;
    } else {
        [_textView.textStorage setAttributedString:releaseNotes];
    }
}

- (void)displayHTMLReleaseNotes:(NSData *)releaseNotes SPU_OBJC_DIRECT
{
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:releaseNotes documentAttributes:NULL];
    [self displayReleaseNotes:attributedString];
}

- (void)displayPlainTextReleaseNotes:(NSData *)releaseNotes encoding:(NSStringEncoding)encoding SPU_OBJC_DIRECT
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
    if (_reply != nil) {
        _reply(SPUUserUpdateChoiceInstall);
        _reply = nil;
    }
}

- (IBAction)installUpdateLater:(id)__unused sender
{
    if (_reply != nil) {
        _reply(SPUUserUpdateChoiceDismiss);
        _reply = nil;
    }
}

- (IBAction)skipUpdate:(id)__unused sender
{
    if (_reply != nil) {
        _reply(SPUUserUpdateChoiceSkip);
        _reply = nil;
    }
}

@end
