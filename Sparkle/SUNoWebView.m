//
//  SUNoWebView.m
//  Sparkle
//
//  Created on 9/11/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUNoWebView.h"
#import "SUWebViewCommon.h"
#import "SULog.h"
#import "SUErrors.h"

#import <AppKit/AppKit.h>

@interface SUNoWebView () <NSTextViewDelegate>
@end

@implementation SUNoWebView
{
    NSScrollView *_scrollView;
    NSTextView *_textView;
    NSString *_fontFamily;
    int _fontPointSize;
}

- (instancetype)initWithFontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize
{
    self = [super init];
    if (self != nil) {
        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
        _textView.delegate = self;
        _scrollView.documentView = _textView;
        _fontFamily = fontFamily;
        _fontPointSize = fontPointSize;
    }
    return self;
}

- (NSView *)view
{
    return _scrollView;
}

- (void)_loadContents:(NSString *)contents baseURL:(NSURL * _Nullable)baseURL inferringHTML:(BOOL)inferringHTML encoding:(NSStringEncoding)encoding completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    NSAttributedString *attributedString;
    if (inferringHTML) {
        NSMutableDictionary<NSString *, id> *options = [NSMutableDictionary dictionary];
        options[NSCharacterEncodingDocumentOption] = @(encoding);
        if (baseURL != nil) {
            options[NSBaseURLDocumentOption] = baseURL;
        }
        
        // Set the default font by injecting default font-size and font-family properties in the HTML
        // See https://stackoverflow.com/questions/19921972/parsing-html-into-nsattributedtext-how-to-set-font
        NSString *htmlStringWithDefaultStyle = [NSString stringWithFormat:@"<span style=\"font-size: %d; font-family: %@\">%@</span>", _fontPointSize, _fontFamily, contents];
        
        NSData *htmlDataWithDefaultStyle = [htmlStringWithDefaultStyle dataUsingEncoding:encoding];
        
        NSAttributedString *htmlAttributedStringWithDefaultStyling;
        if (htmlDataWithDefaultStyle != nil) {
            NSAttributedString *htmlAttributedString = [[NSAttributedString alloc] initWithHTML:htmlDataWithDefaultStyle options:options documentAttributes:nil];
        
            htmlAttributedStringWithDefaultStyling = htmlAttributedString;
        } else {
            htmlAttributedStringWithDefaultStyling = nil;
        }
        
        if (htmlAttributedStringWithDefaultStyling != nil) {
            attributedString = htmlAttributedStringWithDefaultStyling;
        } else {
            // Try falling back without styling
            SULog(SULogLevelError, @"Error: failed to parse HTML data with default styling. Falling back to no styling.");
            
            NSData *htmlData = [contents dataUsingEncoding:encoding];
            NSAttributedString *htmlAttributedString = [[NSAttributedString alloc] initWithHTML:htmlData options:options documentAttributes:nil];
            
            attributedString = htmlAttributedString;
        }
    } else {
        attributedString = [[NSAttributedString alloc] initWithString:contents attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:(CGFloat)_fontPointSize] }];
    }
    
    if (attributedString == nil) {
        completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUReleaseNotesError userInfo:nil]);
    } else {
        [_textView.textStorage setAttributedString:attributedString];
        
        NSSize contentSize = [_scrollView contentSize];
        [_textView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        [_textView setMinSize:NSMakeSize(0.0, contentSize.height)];
        [_textView setMaxSize:NSMakeSize(DBL_MAX, DBL_MAX)];
        [_textView setVerticallyResizable:YES];
        [_textView setHorizontallyResizable:NO];
        [_textView setAutoresizingMask:NSViewWidthSizable];
        [_textView setTextContainerInset:NSMakeSize(8, 8)];
        [_textView setContinuousSpellCheckingEnabled:NO];
        _textView.usesFontPanel = NO;
        _textView.editable = NO;
        
        if (@available(macOS 10.14, *)) {
            _textView.usesAdaptiveColorMappingForDarkAppearance = YES;
        }
        
        [_scrollView setHasVerticalScroller:YES];
        [_scrollView setHasHorizontalScroller:NO];
        
        completionHandler(nil);
    }
}


- (void)loadHTMLString:(NSString *)htmlString baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    [self _loadContents:htmlString baseURL:baseURL inferringHTML:YES encoding:NSUTF8StringEncoding completionHandler:completionHandler];
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)textEncodingName);

    NSStringEncoding encoding;
    if (cfEncoding != kCFStringEncodingInvalidId) {
        encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
    } else {
        encoding = NSUTF8StringEncoding;
    }
    
    NSString *contents = [[NSString alloc] initWithData:data encoding:encoding];
    [self _loadContents:contents baseURL:baseURL inferringHTML:([MIMEType caseInsensitiveCompare:@"text/plain"] != NSOrderedSame) encoding:encoding completionHandler:completionHandler];
}

- (void)stopLoading
{
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    NSURL *linkURL;
    if ([(NSObject *)link isKindOfClass:[NSURL class]]) {
        linkURL = link;
    } else if ([(NSObject *)link isKindOfClass:[NSString class]]) {
        linkURL = [NSURL URLWithString:link];
    } else {
        SULog(SULogLevelDefault, @"Blocked display of %@ link of unknown type", link);
        return YES;
    }
    
    BOOL isAboutBlankURL;
    if (!SUWebViewIsSafeURL(linkURL, &isAboutBlankURL)) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", linkURL.scheme);
        return YES;
    }
    
    return NO;
}

@end

#endif
