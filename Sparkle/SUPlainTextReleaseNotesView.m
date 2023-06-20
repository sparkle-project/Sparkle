//
//  SUPlainReleaseNotesView.m
//  Sparkle
//
//  Created on 9/11/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUPlainTextReleaseNotesView.h"
#import "SUReleaseNotesCommon.h"
#import "SULog.h"
#import "SUErrors.h"

#import <AppKit/AppKit.h>

@interface SUPlainTextReleaseNotesView () <NSTextViewDelegate>
@end

@implementation SUPlainTextReleaseNotesView
{
    NSScrollView *_scrollView;
    NSTextView *_textView;
    NSArray<NSString *> *_customAllowedURLSchemes;
    int _fontPointSize;
}

- (instancetype)initWithFontPointSize:(int)fontPointSize customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes
{
    self = [super init];
    if (self != nil) {
        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
        _textView.delegate = self;
        _scrollView.documentView = _textView;
        _fontPointSize = fontPointSize;
        _customAllowedURLSchemes = customAllowedURLSchemes;
    }
    return self;
}

- (NSView *)view
{
    return _scrollView;
}

- (void)_loadString:(NSString *)contents completionHandler:(void (^)(NSError * _Nullable))completionHandler SPU_OBJC_DIRECT
{
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:contents attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:(CGFloat)_fontPointSize] }];
    
    if (attributedString == nil) {
        completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUReleaseNotesError userInfo:@{NSLocalizedDescriptionKey: @"Failed to create attributed string of contents to load"}]);
        return;
    }
    
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

- (void)loadString:(NSString *)contents baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    [self _loadString:contents completionHandler:completionHandler];
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
    
    if (contents == nil) {
        completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUReleaseNotesError userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert data contents to string"}]);
        return;
    }
    
    [self _loadString:contents completionHandler:completionHandler];
}

- (void)stopLoading
{
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
}

// Links are not insertable yet but this is useful in case we support them in the future
// This is also a defence in case links are somehow insertable
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
    if (!SUReleaseNotesIsSafeURL(linkURL, _customAllowedURLSchemes, &isAboutBlankURL)) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", linkURL.scheme);
        return YES;
    }
    
    return NO;
}

@end

#endif
