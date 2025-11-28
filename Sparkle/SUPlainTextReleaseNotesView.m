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

static void processMarkdownAttributedSubString(NSAttributedString *subAttributedString, NSMutableAttributedString *newAttributedSubString, NSMutableParagraphStyle *paragraphStyle, BOOL canProcessListItem, NSPresentationIntent *intent, NSFont *inputParagraphFont, NSFont *monospacedParagraphFont, NSAttributedString *newlineAttributedString) API_AVAILABLE(macos(12.0))
{
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
    
    NSPresentationIntent *parentIntent = intent.parentIntent;
    if (parentIntent != nil) {
        processMarkdownAttributedSubString(subAttributedString, newAttributedSubString, paragraphStyle, canProcessListItem && !isListItem, parentIntent, font, monospacedParagraphFont, newlineAttributedString);
    }
    
    switch (intent.intentKind) {
        case NSPresentationIntentKindHeader: {
            paragraphStyle.paragraphSpacingBefore += font.pointSize * 0.16;
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            NSMutableAttributedString *headerAttributedString = [subAttributedString mutableCopy];
            
            [headerAttributedString addAttributes:@{NSFontAttributeName: font} range:NSMakeRange(0, headerAttributedString.length)];
            
            [newAttributedSubString appendAttributedString:headerAttributedString];
            
            break;
        }
        case NSPresentationIntentKindParagraph: {
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            NSMutableAttributedString *contentAttributedString = [subAttributedString mutableCopy];
            [contentAttributedString addAttributes:@{NSFontAttributeName: font} range:NSMakeRange(0, contentAttributedString.length)];
            
            [newAttributedSubString appendAttributedString:contentAttributedString];
            
            break;
        }
        case NSPresentationIntentKindListItem: {
            if (canProcessListItem) {
                paragraphStyle.firstLineHeadIndent += intent.indentationLevel * (font.pointSize * 1.5);
                paragraphStyle.headIndent += intent.indentationLevel * (font.pointSize * 1.5);
                
                BOOL insertUnorderedBullet = (parentIntent == nil || parentIntent.intentKind == NSPresentationIntentKindUnorderedList);
                
                if (insertUnorderedBullet) {
                    NSImageSymbolConfiguration *bulletSymbolConfiguration = [NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.textColor];
                    
                    NSImage *bulletSymbol = [NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil];
                    
                    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
                    attachment.image = [bulletSymbol imageWithSymbolConfiguration:bulletSymbolConfiguration];
                    
                    const CGFloat imageScale = font.pointSize / 32.5;
                    const CGFloat yBoundsScaleOffset = 0.25;
                    
                    attachment.bounds = NSMakeRect(0, bulletSymbol.size.height * imageScale * yBoundsScaleOffset, bulletSymbol.size.width * imageScale, bulletSymbol.size.height * imageScale);
                    
                    NSMutableAttributedString *finalBulletAttributedString = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
                    
                    [finalBulletAttributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:@{NSFontAttributeName: font}]];
                    
                    [newAttributedSubString appendAttributedString:finalBulletAttributedString];
                } else {
                    NSAttributedString *listItemAttributedString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ld. ", intent.ordinal] attributes:@{NSFontAttributeName: monospacedParagraphFont}];
                    
                    [newAttributedSubString appendAttributedString:listItemAttributedString];
                }
            }
            
            break;
        }
        case NSPresentationIntentKindThematicBreak: {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.attachmentCell = [[SPUMarkdownHorizontalDividerAttachmentCell alloc] init];

            NSAttributedString *dividerAttributedString =
                [NSAttributedString attributedStringWithAttachment:attachment];
            
            [newAttributedSubString appendAttributedString:dividerAttributedString];
            
            break;
        }
        case NSPresentationIntentKindBlockQuote: {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.attachmentCell = [[SPUMarkdownVerticalAttachmentCell alloc] initWithFont:font];

            NSAttributedString *dividerAttributedString =
                [NSAttributedString attributedStringWithAttachment:attachment];
            
            [newAttributedSubString appendAttributedString:dividerAttributedString];

            break;
        }
        case NSPresentationIntentKindCodeBlock: {
            paragraphStyle.headIndent += font.pointSize * 0.6;
            paragraphStyle.firstLineHeadIndent += font.pointSize * 0.6;
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            NSMutableAttributedString *blockquoteAttributedString = [subAttributedString mutableCopy];
            [blockquoteAttributedString addAttributes:@{NSFontAttributeName: monospacedParagraphFont, NSForegroundColorAttributeName: NSColor.labelColor} range:NSMakeRange(0, blockquoteAttributedString.length)];
            
            [newAttributedSubString appendAttributedString:blockquoteAttributedString];
            
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
    NSFont *paragraphFont = [NSFont systemFontOfSize:defaultFontPointSize];
    NSFont *monospacedParagraphFont = [NSFont monospacedSystemFontOfSize:defaultFontPointSize weight:NSFontWeightRegular];
    
    NSAttributedString *originalAttributedString = [[NSAttributedString alloc] initWithMarkdownString:contents options:nil baseURL:nil error:outError];
    
    NSMutableAttributedString *newAttributedString = [[NSMutableAttributedString alloc] init];
    
    NSAttributedString *newlineAttributedString = [[NSAttributedString alloc] initWithString:@"\n"];
    
    [originalAttributedString enumerateAttribute:NSPresentationIntentAttributeName inRange:NSMakeRange(0, originalAttributedString.length) options:0 usingBlock:^(NSPresentationIntent *intent, NSRange range, BOOL * _Nonnull __unused stop) {
        
        NSAttributedString *subAttributedString = [originalAttributedString attributedSubstringFromRange:range];
        
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.paragraphSpacingBefore = 0;
        paragraphStyle.paragraphSpacing = 0;
        paragraphStyle.headIndent = 0;
        paragraphStyle.firstLineHeadIndent = 0;
        
        NSMutableAttributedString *newAttributedSubString = [[NSMutableAttributedString alloc] init];
        
        BOOL canProcessListItem = YES;
        processMarkdownAttributedSubString(subAttributedString, newAttributedSubString, paragraphStyle, canProcessListItem, intent, paragraphFont, monospacedParagraphFont, newlineAttributedString);
        
        [newAttributedSubString addAttributes:@{NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(0, newAttributedSubString.length)];
        
        [newAttributedString appendAttributedString:newAttributedSubString];
        [newAttributedString appendAttributedString:newlineAttributedString];
    }];
    
    return newAttributedString;
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
