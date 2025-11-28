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
API_AVAILABLE(macos(12.0))
@interface SPUMarkdownVerticalAttachmentCell : NSTextAttachmentCell
@end

@implementation SPUMarkdownVerticalAttachmentCell
{
    NSTextLayoutManager *_textLayoutManager;
    NSFont *_font;
    
    NSInteger _textOffset;
}

- (instancetype)initWithTextLayoutManager:(NSTextLayoutManager *)textLayoutManager textOffset:(NSInteger)textOffset font:(NSFont *)font
{
    self = [super init];
    if (self != nil) {
        _textLayoutManager = textLayoutManager;
        _font = font;
        _textOffset = textOffset;
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
    NSTextContentManager *textContentManager = _textLayoutManager.textContentManager;
    id<NSTextLocation> textLocation = [textContentManager locationFromLocation:textContentManager.documentRange.location withOffset:_textOffset];
    
    NSTextLayoutFragment *textLayoutFragment = [_textLayoutManager textLayoutFragmentForLocation:textLocation];
    
    const CGFloat lineWidth = 2.0;
    CGFloat xPosition = cellFrame.origin.x + lineWidth / 2.0;
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    
    NSPoint beginPoint = NSMakePoint(xPosition, cellFrame.origin.y + cellFrame.size.height - _font.ascender);
    NSPoint endPoint = NSMakePoint(beginPoint.x, beginPoint.y + (_font.ascender + -(_font.descender) + _font.leading) * textLayoutFragment.textLineFragments.count);
    
    [path moveToPoint:NSMakePoint(beginPoint.x, beginPoint.y)];
    [path lineToPoint:NSMakePoint(endPoint.x, endPoint.y)];

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
#if DEBUG
    id _textViewSwitchedToTextKit1Observer;
#endif
    NSArray<NSString *> *_customAllowedURLSchemes;
    int _fontPointSize;
    
    BOOL _prefersMarkdown;
}

- (instancetype)initWithFontPointSize:(int)fontPointSize prefersMarkdown:(BOOL)prefersMarkdown customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes
{
    self = [super init];
    if (self != nil) {
        _fontPointSize = fontPointSize;
        _customAllowedURLSchemes = customAllowedURLSchemes;
        _prefersMarkdown = prefersMarkdown;
        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        
        if (@available(macOS 12, *)) {
            // Create NSTextView using TextKit 2
            // https://developer.apple.com/documentation/appkit/nstextview/1449347-initwithframe
            
            NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(0, (CGFloat)FLT_MAX)];
            textContainer.widthTracksTextView = YES;
            
            NSTextLayoutManager *textLayoutManager = [[NSTextLayoutManager alloc] init];
            textLayoutManager.textContainer = textContainer;
            
            NSTextContentStorage *textContentStorage = [[NSTextContentStorage alloc] init];
            [textContentStorage addTextLayoutManager:textLayoutManager];
            
            _textView = [[NSTextView alloc] initWithFrame:NSZeroRect textContainer:textLayoutManager.textContainer];
            
#if DEBUG
            _textViewSwitchedToTextKit1Observer = [NSNotificationCenter.defaultCenter addObserverForName:NSTextViewDidSwitchToNSLayoutManagerNotification object:_textView queue:nil usingBlock:^(NSNotification * _Nonnull __unused notification) {
                SULog(SULogLevelError, @"Error: Plain text release notes text view switched to TextKit 1. This should not happen. Was some TextKit 1 API called that is causing this?");
            }];
#endif
        } else {
            _textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
        }
        
        _textView.delegate = self;
        _scrollView.documentView = _textView;
    }
    return self;
}

#if DEBUG
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:_textViewSwitchedToTextKit1Observer];
}
#endif

- (NSView *)view
{
    return _scrollView;
}

static void processMarkdownFragmentAttributedString(NSAttributedString *fragmentAttributedString, NSMutableAttributedString *outputAttributedSubString, NSMutableParagraphStyle *paragraphStyle, BOOL canProcessListItem, NSMutableSet<NSPresentationIntent *> *previousVisitedListItemIntents, NSPresentationIntent *intent, NSFont *inputParagraphFont, NSFont *monospacedParagraphFont, NSAttributedString *tabAttributedString, NSAttributedString *newlineAttributedString, NSAttributedString *listBulletAttributedString, NSTextLayoutManager *textLayoutManager) API_AVAILABLE(macos(12.0))
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
        processMarkdownFragmentAttributedString(fragmentAttributedString, outputAttributedSubString, paragraphStyle, canProcessListItem && !isListItem, previousVisitedListItemIntents, parentIntent, font, monospacedParagraphFont, tabAttributedString, newlineAttributedString, listBulletAttributedString, textLayoutManager);
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
            // Also avoid processing list items that were processed from previous passes / fragments
            if (canProcessListItem) {
                CGFloat firstLineIdentation = intent.indentationLevel * (font.pointSize * 1.5);
                paragraphStyle.firstLineHeadIndent += firstLineIdentation;
                
                // Advance subsequent lines and text that wraps to next line by next tab interval past the firstLineIdentation
                CGFloat defaultTabInterval = paragraphStyle.defaultTabInterval;
                paragraphStyle.headIndent += ceil(firstLineIdentation / defaultTabInterval) * defaultTabInterval;
                
                BOOL didVisitListItemFromPreviousPass = [previousVisitedListItemIntents containsObject:intent];
                BOOL insertUnorderedBullet = (parentIntent == nil || parentIntent.intentKind == NSPresentationIntentKindUnorderedList);
                
                if (!didVisitListItemFromPreviousPass) {
                    if (insertUnorderedBullet) {
                        [outputAttributedSubString appendAttributedString:listBulletAttributedString];
                    } else {
                        NSString *ordinalStringWithSpacing = [NSString stringWithFormat:@"%ld.", intent.ordinal];
                        NSAttributedString *listItemAttributedString = [[NSAttributedString alloc] initWithString:ordinalStringWithSpacing attributes:@{NSFontAttributeName: font}];
                        
                        [outputAttributedSubString appendAttributedString:listItemAttributedString];
                    }
                    
                    [previousVisitedListItemIntents addObject:intent];
                }
                
                [outputAttributedSubString appendAttributedString:tabAttributedString];
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
            // Each text fragment will get its own preceding vertical line. These lines are not 'connected' which is a limitation for now.
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.attachmentCell = [[SPUMarkdownVerticalAttachmentCell alloc] initWithTextLayoutManager:textLayoutManager textOffset:(NSInteger)outputAttributedSubString.length font:font];

            NSAttributedString *dividerAttributedString =
                [NSAttributedString attributedStringWithAttachment:attachment];
            
            [outputAttributedSubString appendAttributedString:dividerAttributedString];
            // Advance text that wraps to next line by this divider width
            paragraphStyle.headIndent += dividerAttributedString.size.width;

            break;
        }
        case NSPresentationIntentKindCodeBlock: {
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            // A parent of a code block could be a block quote or list item
            // It's more correct to use tab rather than leading paragraph indentation in this case
            [outputAttributedSubString appendAttributedString:tabAttributedString];
            // Advance text that wraps to next line by next tab interval
            paragraphStyle.headIndent += paragraphStyle.defaultTabInterval;
            
            NSMutableAttributedString *blockquoteAttributedString = [fragmentAttributedString mutableCopy];
            [blockquoteAttributedString addAttributes:@{NSFontAttributeName: monospacedParagraphFont, NSForegroundColorAttributeName: NSColor.labelColor} range:NSMakeRange(0, blockquoteAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:blockquoteAttributedString];
            
            break;
        }
        
        case NSPresentationIntentKindOrderedList:
        case NSPresentationIntentKindUnorderedList:
        // Note: TextKit 2 doesn't support NSTextTable
        // Tables don't show up in release notes often, so they're not that worthwhile supporting
        case NSPresentationIntentKindTable:
        case NSPresentationIntentKindTableHeaderRow:
        case NSPresentationIntentKindTableRow:
        case NSPresentationIntentKindTableCell:
            break;
    }
}

static NSAttributedString * _Nullable makeMarkdownAttributedString(NSString *contents, CGFloat defaultFontPointSize, NSTextLayoutManager *textLayoutManager, NSError * __autoreleasing *outError) API_AVAILABLE(macos(12.0))
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
        
        const CGFloat imageScale = paragraphFont.pointSize / 32.5;
        const CGFloat yBoundsScaleOffset = 0.25;
        
        attachment.bounds = NSMakeRect(0, bulletSymbol.size.height * imageScale * yBoundsScaleOffset, bulletSymbol.size.width * imageScale, bulletSymbol.size.height * imageScale);
        attachment.image = [bulletSymbol imageWithSymbolConfiguration:bulletSymbolConfiguration];
        
        listBulletAttributedString = [NSAttributedString attributedStringWithAttachment:attachment];
    }
    
    NSAttributedString *tabAttributedString = [[NSAttributedString alloc] initWithString:@"\t" attributes:@{NSFontAttributeName: paragraphFont}];
    
    NSMutableSet<NSPresentationIntent *> *previousVisitedListItemIntents = [[NSMutableSet alloc] init];
    
    // Enumerate through every presentation intent fragment and create a new attributed string that we append to the output
    // Foundation handles formatting some things for us already in the attributed string such as bold/itatlics and hyperlinks,
    // but we need to handle formatting paragraphs, headers, lists, block quotes, etc in the attributed string.
    [originalAttributedString enumerateAttribute:NSPresentationIntentAttributeName inRange:NSMakeRange(0, originalAttributedString.length) options:0 usingBlock:^(NSPresentationIntent *intent, NSRange presentationIntentRange, BOOL * _Nonnull __unused stopPresentationIntentEnumeration) {
        
        // Split the presentation intent by lines so we treat every line as a separate paragraph so we present them properly (with correct indentation / tabs)
        // Normally multiple lines aren't in the same paragraph, but this can happen in some cases like code blocks
        [originalAttributedString.string enumerateSubstringsInRange:presentationIntentRange options:NSStringEnumerationByLines usingBlock:^(NSString * _Nullable __unused substring, NSRange substringRange, NSRange __unused enclosingRange, BOOL * _Nonnull __unused stopLineEnumeration) {
            // Insert newline after outputting previous paragraph
            // This check ensures an extra newline is not inserted after the last outputted paragraph
            if (outputAttributedString.length > 0) {
                [outputAttributedString appendAttributedString:newlineAttributedString];
            }
            
            NSAttributedString *fragmentAttributedString = [originalAttributedString attributedSubstringFromRange:substringRange];
            
            // Properties of the paragraph start as 0 and later get incremented based on what is processed
            NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
            paragraphStyle.paragraphSpacingBefore = 0;
            paragraphStyle.paragraphSpacing = 0;
            paragraphStyle.headIndent = 0;
            paragraphStyle.firstLineHeadIndent = 0;
            
            // Assume tabs won't be used in headers so we'll just use regular paragraph font size
            paragraphStyle.tabStops = @[];
            paragraphStyle.defaultTabInterval = paragraphFont.pointSize * 1.38;
            
            NSUInteger previousOutputLength = outputAttributedString.length;
            
            BOOL canProcessListItem = YES;
            processMarkdownFragmentAttributedString(fragmentAttributedString, outputAttributedString, paragraphStyle, canProcessListItem, previousVisitedListItemIntents, intent, paragraphFont, monospacedParagraphFont, tabAttributedString, newlineAttributedString, listBulletAttributedString, textLayoutManager);
            
            [outputAttributedString addAttributes:@{NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(previousOutputLength, outputAttributedString.length - previousOutputLength)];
        }];
    }];
    
    return outputAttributedString;
}

- (void)_loadString:(NSString *)contents completionHandler:(void (^)(NSError * _Nullable))completionHandler SPU_OBJC_DIRECT
{
    NSAttributedString *attributedString = nil;
    if (_prefersMarkdown) {
        if (@available(macOS 12, *)) {
            
            NSTextLayoutManager *textLayoutManager = _textView.textLayoutManager;
            
            NSError *markdownError = nil;
            attributedString = makeMarkdownAttributedString(contents, (CGFloat)_fontPointSize, textLayoutManager, &markdownError);
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
