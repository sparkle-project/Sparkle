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
@interface SPUMarkdownDividerAttachmentCell : NSTextAttachmentCell
@end

@implementation SPUMarkdownDividerAttachmentCell

- (NSSize)cellSize
{
    return NSMakeSize(0, 10);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    CGFloat midY = NSMidY(cellFrame);

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(0, midY)];
    [path lineToPoint:NSMakePoint(controlView.bounds.size.width, midY)];

    [[NSColor separatorColor] setStroke];
    [path setLineWidth:1.0];
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

static NSAttributedString * _Nullable makeMarkdownAttributedString(NSString *contents, CGFloat defaultFontPointSize, NSError * __autoreleasing *outError) API_AVAILABLE(macos(12.0))
{
    NSFont *paragraphFont = [NSFont systemFontOfSize:defaultFontPointSize];
    NSFont *monospacedParagraphFont = [NSFont monospacedSystemFontOfSize:defaultFontPointSize weight:NSFontWeightRegular];
    
    NSAttributedString *originalAttributedString = [[NSAttributedString alloc] initWithMarkdownString:contents options:nil baseURL:nil error:outError];
    
    NSMutableAttributedString *newAttributedString = [[NSMutableAttributedString alloc] init];
    
    NSAttributedString *newlineAttributedString = [[NSAttributedString alloc] initWithString:@"\n"];
    
    [originalAttributedString enumerateAttribute:NSPresentationIntentAttributeName inRange:NSMakeRange(0, originalAttributedString.length) options:0 usingBlock:^(NSPresentationIntent *intent, NSRange range, BOOL * _Nonnull __unused stop) {
        
        NSAttributedString *subAttributedString = [originalAttributedString attributedSubstringFromRange:range];
        
        NSLog(@"Parent intent: %@", intent.parentIntent);
        
        NSLog(@"Subattributed string: %@", subAttributedString);
        
        switch (intent.intentKind) {
            case NSPresentationIntentKindHeader: {
                NSInteger level = intent.headerLevel;
                NSFont *font;
                switch (level) {
                    case 1:
                        font = [NSFont boldSystemFontOfSize:(CGFloat)defaultFontPointSize + 7.0];
                        break;
                    case 2:
                        font = [NSFont boldSystemFontOfSize:(CGFloat)defaultFontPointSize + 4.0];
                        break;
                    case 3:
                        font = [NSFont boldSystemFontOfSize:(CGFloat)defaultFontPointSize + 2.0];
                        break;
                    default:
                        font = [NSFont boldSystemFontOfSize:(CGFloat)defaultFontPointSize + 1.0];
                        break;
                }
                
                NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
                paragraphStyle.paragraphSpacingBefore = 4.0;
                paragraphStyle.paragraphSpacing = 8.0;
                
                NSMutableAttributedString *headerAttributedString = [subAttributedString mutableCopy];
                
                [headerAttributedString addAttributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(0, headerAttributedString.length)];
                
                [newAttributedString appendAttributedString:headerAttributedString];
                [newAttributedString appendAttributedString:newlineAttributedString];
                
                break;
            }
            case NSPresentationIntentKindParagraph: {
                NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
                paragraphStyle.paragraphSpacing = 4.0;
                
                NSMutableAttributedString *paragraphAttributedString = [[NSMutableAttributedString alloc] init];
                
                NSPresentationIntent *parentIntent = intent.parentIntent;
                if (parentIntent != nil) {
                    switch (parentIntent.intentKind) {
                        case NSPresentationIntentKindListItem: {
                            paragraphStyle.firstLineHeadIndent = 20.0 * parentIntent.indentationLevel;
                            paragraphStyle.headIndent = 20.0 * parentIntent.indentationLevel;
                            
                            NSImage *bulletSymbol = [NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil];
                            
                            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
                            attachment.image = bulletSymbol;
                            
                            const CGFloat imageScale = 0.4;
                            const CGFloat yBoundsScaleOffset = 0.1;
                            attachment.bounds = NSMakeRect(0, bulletSymbol.size.height * yBoundsScaleOffset, bulletSymbol.size.width * imageScale, bulletSymbol.size.height * imageScale);
                            
                            NSMutableAttributedString *finalBulletAttributedString = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
                            
                            [finalBulletAttributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
                            
                            [finalBulletAttributedString addAttributes:@{NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(0, finalBulletAttributedString.length)];
                            
                            [paragraphAttributedString appendAttributedString:finalBulletAttributedString];
                            
                            break;
                        }
                        default:
                            break;
                    }
                }
                
                NSMutableAttributedString *contentAttributedString = [subAttributedString mutableCopy];
                [contentAttributedString addAttributes:@{NSFontAttributeName: paragraphFont, NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(0, contentAttributedString.length)];
                
                [paragraphAttributedString appendAttributedString:contentAttributedString];
                
                [newAttributedString appendAttributedString:paragraphAttributedString];
                [newAttributedString appendAttributedString:newlineAttributedString];
                
                break;
            }
            case NSPresentationIntentKindThematicBreak: {
                NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
                attachment.attachmentCell = [[SPUMarkdownDividerAttachmentCell alloc] init];

                NSAttributedString *dividerAttributedString =
                    [NSAttributedString attributedStringWithAttachment:attachment];
                
                [newAttributedString appendAttributedString:dividerAttributedString];
                [newAttributedString appendAttributedString:newlineAttributedString];
                break;
            }
            case NSPresentationIntentKindCodeBlock: {
                NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
                style.headIndent = 6;
                style.firstLineHeadIndent = 6;
                style.paragraphSpacing = 2;
                style.paragraphSpacingBefore = 4;

                NSDictionary *attrs = @{
                    NSFontAttributeName: monospacedParagraphFont,
                    NSParagraphStyleAttributeName: style,
                    NSForegroundColorAttributeName: NSColor.labelColor
                };
                
                NSMutableAttributedString *blockquoteAttributedString = [subAttributedString mutableCopy];
                [blockquoteAttributedString addAttributes:attrs range:NSMakeRange(0, blockquoteAttributedString.length)];
                
                [newAttributedString appendAttributedString:blockquoteAttributedString];
                [newAttributedString appendAttributedString:newlineAttributedString];
                
                break;
            }
            default:
                break;
        }
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
