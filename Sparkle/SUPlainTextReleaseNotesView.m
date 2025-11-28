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

// Divider attachment cell used for markdown horizontal line breaks
API_AVAILABLE(macos(10.14))
@interface SPUMarkdownHorizontalDividerAttachmentCell : NSTextAttachmentCell
@end

@implementation SPUMarkdownHorizontalDividerAttachmentCell

- (NSSize)cellSize
{
    // Minimum width needs to be at least 1
    return NSMakeSize(1.0, 10.0);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)view
{
    CGFloat yPosition = NSMidY(cellFrame);
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(0.0, yPosition)];
    [path lineToPoint:NSMakePoint(view.bounds.size.width, yPosition)];

    [[NSColor separatorColor] setStroke];
    [path setLineWidth:1.0];
    [path stroke];
}

@end

// Divider attachment cell used for markdown block quotes
API_AVAILABLE(macos(10.14))
@interface SPUMarkdownVerticalAttachmentCell : NSTextAttachmentCell
@end

@implementation SPUMarkdownVerticalAttachmentCell
{
    NSFont *_font;
}

- (instancetype)initWithFont:(NSFont *)font
{
    self = [super init];
    if (self != nil) {
        _font = font;
    }
    return self;
}

- (NSSize)cellSize
{
    // Minimum height needs to be at least 1
    return NSMakeSize(10.0, 1.0);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)view
{
    const CGFloat lineWidth = 2.0;
    CGFloat xPosition = cellFrame.origin.x + lineWidth / 2.0;
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(xPosition, cellFrame.origin.y + cellFrame.size.height - _font.ascender)];
    [path lineToPoint:NSMakePoint(xPosition, cellFrame.origin.y + cellFrame.size.height + -(_font.descender))];

    [[NSColor separatorColor] setStroke];
    [path setLineWidth:lineWidth];
    [path stroke];
}

@end

@interface SUPlainTextReleaseNotesView () <NSTextViewDelegate>
@end

@implementation SUPlainTextReleaseNotesView
{
    NSScrollView *_scrollView;
    NSTextView *_textView;
    NSArray<NSString *> *_customAllowedURLSchemes;
    int _fontPointSize;
    
    BOOL _prefersMarkdown;
}

- (instancetype)initWithFontPointSize:(int)fontPointSize prefersMarkdown:(BOOL)prefersMarkdown customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes
{
    self = [super init];
    if (self != nil) {
        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
        _textView.delegate = self;
        _scrollView.documentView = _textView;
        _fontPointSize = fontPointSize;
        _customAllowedURLSchemes = customAllowedURLSchemes;
        _prefersMarkdown = prefersMarkdown;
    }
    return self;
}

- (NSView *)view
{
    return _scrollView;
}

static void processMarkdownFragmentAttributedString(NSAttributedString *fragmentAttributedString, NSMutableAttributedString *outputAttributedSubString, NSMutableParagraphStyle *paragraphStyle, BOOL canProcessListItem, NSPresentationIntent *intent, NSFont *inputParagraphFont, NSFont *monospacedParagraphFont, NSAttributedString *newlineAttributedString, NSAttributedString *listBulletAttributedString) API_AVAILABLE(macos(12.0))
{
    // Pre-pass processing of intent
    // This info must be computed before processing parent intent
    BOOL isListItem = NO;
    NSFont *font = inputParagraphFont;
    switch (intent.intentKind) {
        case NSPresentationIntentKindHeader:
            switch (intent.headerLevel) {
                case 1:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize + 7.0];
                    break;
                case 2:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize + 4.0];
                    break;
                case 3:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize + 2.0];
                    break;
                default:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize + 1.0];
                    break;
            }
            break;
        case NSPresentationIntentKindListItem:
            isListItem = YES;
            break;
        case NSPresentationIntentKindParagraph:
        case NSPresentationIntentKindThematicBreak:
        case NSPresentationIntentKindBlockQuote:
        case NSPresentationIntentKindCodeBlock:
        case NSPresentationIntentKindOrderedList:
        case NSPresentationIntentKindUnorderedList:
        case NSPresentationIntentKindTable:
        case NSPresentationIntentKindTableHeaderRow:
        case NSPresentationIntentKindTableRow:
        case NSPresentationIntentKindTableCell:
            break;
    }
    
    // Process parent intent if available
    // A paragraph's intent may be a list item, or a block quote for example. A header's parent intent could be a block quote.
    // In these cases, we may pre-append attributed string to the output before processing current intent.
    NSPresentationIntent *parentIntent = intent.parentIntent;
    if (parentIntent != nil) {
        processMarkdownFragmentAttributedString(fragmentAttributedString, outputAttributedSubString, paragraphStyle, canProcessListItem && !isListItem, parentIntent, font, monospacedParagraphFont, newlineAttributedString, listBulletAttributedString);
    }
    
    // Process the current intent
    switch (intent.intentKind) {
        case NSPresentationIntentKindHeader: {
            paragraphStyle.paragraphSpacingBefore += font.pointSize * 0.16;
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            NSMutableAttributedString *headerAttributedString = [fragmentAttributedString mutableCopy];
            
            [headerAttributedString addAttributes:@{NSFontAttributeName: font} range:NSMakeRange(0, headerAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:headerAttributedString];
            
            break;
        }
        case NSPresentationIntentKindParagraph: {
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            NSMutableAttributedString *contentAttributedString = [fragmentAttributedString mutableCopy];
            [contentAttributedString addAttributes:@{NSFontAttributeName: font} range:NSMakeRange(0, contentAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:contentAttributedString];
            
            break;
        }
        case NSPresentationIntentKindListItem: {
            // We only process (the innermost first) list item once when we encounter nested lists,
            // to avoid outputting multiple list bullets
            if (canProcessListItem) {
                paragraphStyle.firstLineHeadIndent += intent.indentationLevel * (font.pointSize * 1.5);
                paragraphStyle.headIndent += intent.indentationLevel * (font.pointSize * 1.5);
                
                BOOL insertUnorderedBullet = (parentIntent == nil || parentIntent.intentKind == NSPresentationIntentKindUnorderedList);
                
                if (insertUnorderedBullet) {
                    [outputAttributedSubString appendAttributedString:listBulletAttributedString];
                } else {
                    NSAttributedString *listItemAttributedString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ld. ", intent.ordinal] attributes:@{NSFontAttributeName: monospacedParagraphFont}];
                    
                    [outputAttributedSubString appendAttributedString:listItemAttributedString];
                }
            }
            
            break;
        }
        case NSPresentationIntentKindThematicBreak: {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.attachmentCell = [[SPUMarkdownHorizontalDividerAttachmentCell alloc] init];

            NSAttributedString *dividerAttributedString =
                [NSAttributedString attributedStringWithAttachment:attachment];
            
            [outputAttributedSubString appendAttributedString:dividerAttributedString];
            
            break;
        }
        case NSPresentationIntentKindBlockQuote: {
            // Multiple levels of block quotes are handled (e.g. parent intent could be another block quote).
            // Each line will get its own preceding vertical line. These lines are not 'connected' which is a limitation for now.
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.attachmentCell = [[SPUMarkdownVerticalAttachmentCell alloc] initWithFont:font];

            NSAttributedString *dividerAttributedString =
                [NSAttributedString attributedStringWithAttachment:attachment];
            
            [outputAttributedSubString appendAttributedString:dividerAttributedString];

            break;
        }
        case NSPresentationIntentKindCodeBlock: {
            paragraphStyle.headIndent += font.pointSize * 0.6;
            paragraphStyle.firstLineHeadIndent += font.pointSize * 0.6;
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            NSMutableAttributedString *blockquoteAttributedString = [fragmentAttributedString mutableCopy];
            [blockquoteAttributedString addAttributes:@{NSFontAttributeName: monospacedParagraphFont, NSForegroundColorAttributeName: NSColor.labelColor} range:NSMakeRange(0, blockquoteAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:blockquoteAttributedString];
            
            break;
        }
        
        case NSPresentationIntentKindOrderedList:
        case NSPresentationIntentKindUnorderedList:
        case NSPresentationIntentKindTable:
        case NSPresentationIntentKindTableHeaderRow:
        case NSPresentationIntentKindTableRow:
        case NSPresentationIntentKindTableCell:
            break;
    }
}

static NSAttributedString * _Nullable makeMarkdownAttributedString(NSString *contents, CGFloat defaultFontPointSize, NSError * __autoreleasing *outError) API_AVAILABLE(macos(12.0))
{
    NSAttributedString *originalAttributedString = [[NSAttributedString alloc] initWithMarkdownString:contents options:nil baseURL:nil error:outError];
    if (originalAttributedString == nil) {
        return nil;
    }
    
    // Create our fonts and cache some common attributed strings up front (list bullets, newline)
    
    NSFont *paragraphFont = [NSFont systemFontOfSize:defaultFontPointSize];
    NSFont *monospacedParagraphFont = [NSFont monospacedSystemFontOfSize:defaultFontPointSize weight:NSFontWeightRegular];
    
    NSMutableAttributedString *outputAttributedString = [[NSMutableAttributedString alloc] init];
    
    NSAttributedString *newlineAttributedString = [[NSAttributedString alloc] initWithString:@"\n"];
    
    NSAttributedString *listBulletAttributedString;
    {
        // Create a list bullet by using a SF symbol that uses a dynamic color appropriate for switching between light/dark mode,
        // and we can scale the image to what we need (regular unicode bullet point characters are scaled too small or too big and may not be offsetted right)
        // Perhaps we could have created a custom attachment cell class instead, but this works
        NSImageSymbolConfiguration *bulletSymbolConfiguration = [NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.textColor];
        
        NSImage *bulletSymbol = [NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil];
        
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = [bulletSymbol imageWithSymbolConfiguration:bulletSymbolConfiguration];
        
        const CGFloat imageScale = paragraphFont.pointSize / 32.5;
        const CGFloat yBoundsScaleOffset = 0.25;
        
        attachment.bounds = NSMakeRect(0, bulletSymbol.size.height * imageScale * yBoundsScaleOffset, bulletSymbol.size.width * imageScale, bulletSymbol.size.height * imageScale);
        
        NSMutableAttributedString *finalBulletAttributedString = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
        
        [finalBulletAttributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:@{NSFontAttributeName: paragraphFont}]];
        
        listBulletAttributedString = [finalBulletAttributedString copy];
    }
    
    // Enumerate through every presentation intent fragment and create a new attributed string that we append to the output
    // Foundation handles formatting some things for us already in the attributed string such as bold/itatlics and hyperlinks,
    // but we need to handle formatting paragraphs, headers, lists, block quotes, etc in the attributed string.
    [originalAttributedString enumerateAttribute:NSPresentationIntentAttributeName inRange:NSMakeRange(0, originalAttributedString.length) options:0 usingBlock:^(NSPresentationIntent *intent, NSRange range, BOOL * _Nonnull __unused stop) {
        
        NSAttributedString *fragmentAttributedString = [originalAttributedString attributedSubstringFromRange:range];
        
        // Properties of the paragraph start as 0 and later get incremented based on what is processed
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.paragraphSpacingBefore = 0;
        paragraphStyle.paragraphSpacing = 0;
        paragraphStyle.headIndent = 0;
        paragraphStyle.firstLineHeadIndent = 0;
        
        NSMutableAttributedString *fragmentOutputAttributedString = [[NSMutableAttributedString alloc] init];
        
        BOOL canProcessListItem = YES;
        processMarkdownFragmentAttributedString(fragmentAttributedString, fragmentOutputAttributedString, paragraphStyle, canProcessListItem, intent, paragraphFont, monospacedParagraphFont, newlineAttributedString, listBulletAttributedString);
        
        [fragmentOutputAttributedString addAttributes:@{NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(0, fragmentOutputAttributedString.length)];
        
        [outputAttributedString appendAttributedString:fragmentOutputAttributedString];
        [outputAttributedString appendAttributedString:newlineAttributedString];
    }];
    
    return outputAttributedString;
}

- (void)_loadString:(NSString *)contents completionHandler:(void (^)(NSError * _Nullable))completionHandler SPU_OBJC_DIRECT
{
    NSAttributedString *attributedString = nil;
    if (_prefersMarkdown) {
        if (@available(macOS 12, *)) {
            NSError *markdownError = nil;
            attributedString = makeMarkdownAttributedString(contents, (CGFloat)_fontPointSize, &markdownError);
            if (attributedString == nil) {
                SULog(SULogLevelError, @"Failed to load markdown contents with error: %@. Falling back to plain text.", markdownError.localizedDescription);
            }
        } else {
            SULog(SULogLevelDefault, @"Warning: falling back to plain text because markdown support requires macOS 12 or newer");
        }
    }
    
    if (attributedString == nil) {
        // Fall back to plain text
        attributedString = [[NSAttributedString alloc] initWithString:contents attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:(CGFloat)_fontPointSize] }];
    }
    
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
