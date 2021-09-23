//
//  SUWKWebView.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUWKWebView.h"
#import "SUWebViewCommon.h"
#import "SULog.h"
#import "SUErrors.h"
#import <WebKit/WebKit.h>

@interface WKWebView (Private)

- (void)_setDrawsBackground:(BOOL)drawsBackground;
- (void)_setDrawsTransparentBackground:(BOOL)drawsTransparentBackground;

@end

@interface SUWKWebView () <WKNavigationDelegate>

@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic) WKNavigation *currentNavigation;
@property (nonatomic) void (^completionHandler)(NSError * _Nullable);
@property (nonatomic) BOOL drawsWebViewBackground;

@end

@implementation SUWKWebView

@synthesize webView = _webView;
@synthesize currentNavigation = _currentNavigation;
@synthesize completionHandler = _completionHandler;
@synthesize drawsWebViewBackground = _drawsWebViewBackground;

static WKUserScript *_userScriptWithInjectedStyleSource(NSString *styleSource)
{
    // We must remove newlines when inserting the style source in this interpolated string below
    NSString *strippedStyleSource = [styleSource stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    
    NSString *scriptSource = [NSString stringWithFormat:
        @"var style = document.createElement('style');\n"
        @"style.innerHTML = '%@'\n"
        @"var head = document.head;\n"
        @"if (head.firstChild) {"
        @"\tdocument.head.insertBefore(style, document.head.firstChild);\n"
        @"} else {\n"
        @"\tdocument.head.appendChild(style)\n"
        @"}", strippedStyleSource];
    
    return [[WKUserScript alloc] initWithSource:scriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
}

- (instancetype)initWithColorStyleSheetLocation:(NSURL *)colorStyleSheetLocation fontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize javaScriptEnabled:(BOOL)javaScriptEnabled
{
    self = [super init];
    if (self != nil) {
        // Synchronize with web view defaulting to drawing background to avoid unnecessary invocations in -setDrawsBackground:
        _drawsWebViewBackground = YES;
        
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        
        // Note: this javaScriptEnabled property is deprecated in favor of another webpage preference property,
        // that involves implementing a delegate method that is only available on macOS 11.. to get it properly working.
        // To simplify things, just rely on deprecated property for now.
        // Future reader: if you change how JS is disabled, please be sure to test that JS code is properly disabled in HTML release notes.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        configuration.preferences.javaScriptEnabled = javaScriptEnabled;
#pragma clang diagnostic pop
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        
        NSError *colorStyleContentsError = nil;
        NSString *colorStyleContents = [NSString stringWithContentsOfURL:colorStyleSheetLocation encoding:NSUTF8StringEncoding error:&colorStyleContentsError];
        
        WKUserContentController *userContentController = [[WKUserContentController alloc] init];
        
        NSString *fontStyleContents = [NSString stringWithFormat:@"body { font-family: %@; font-size: %dpx; }", fontFamily, fontPointSize];
        
        NSString *finalStyleContents;
        if (colorStyleContents == nil) {
            SULog(SULogLevelError, @"Failed to load style contents from %@ with %@", colorStyleSheetLocation, colorStyleContentsError);
            
            finalStyleContents = fontStyleContents;
        } else {
            finalStyleContents = [NSString stringWithFormat:@"%@ %@", fontStyleContents, colorStyleContents];
        }
        
        // Note: we can still execute javascript via WKUserScript even if javascript is otherwise disabled from the web content
        // In fact, we must execute javascript to properly inject our default CSS style into the DOM
        // Legacy WebView has exposed methods for custom stylesheets and default fonts,
        // but WKWebView seems to forgo that type of API surface in favor of user scripts like this
        [userContentController addUserScript:_userScriptWithInjectedStyleSource(finalStyleContents)];
        configuration.userContentController = userContentController;
        
        _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
        _webView.navigationDelegate = self;
    }
    return self;
}

- (NSView *)view
{
    return self.webView;
}

- (void)loadHTMLString:(NSString *)htmlString baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    self.completionHandler = [completionHandler copy];
    
    self.currentNavigation = [self.webView loadHTMLString:htmlString baseURL:baseURL];
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    self.completionHandler = [completionHandler copy];

    self.currentNavigation = [self.webView loadData:data MIMEType:MIMEType characterEncodingName:textEncodingName baseURL:baseURL];
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
    if (self.drawsWebViewBackground != drawsBackground) {
        // Unfortunately we have to rely on a private API
        // FB7539179: https://github.com/feedback-assistant/reports/issues/81 | https://bugs.webkit.org/show_bug.cgi?id=155550
        // But it seems like others are already relying on it, passed App Review, and apps couldn't be broken due to compatibility
        if (@available(macOS 10.12, *)) {
            if ([self.webView respondsToSelector:@selector(_setDrawsBackground:)]) {
                [self.webView _setDrawsBackground:drawsBackground];
            }
        } else {
            if ([self.webView respondsToSelector:@selector(_setDrawsTransparentBackground:)]) {
                [self.webView _setDrawsTransparentBackground:!drawsBackground];
            }
        }
        
        self.drawsWebViewBackground = drawsBackground;
    }
}

- (void)stopLoading
{
    self.completionHandler = nil;
    [self.webView stopLoading];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (navigation == self.currentNavigation) {
        if (self.completionHandler != nil) {
            self.completionHandler(nil);
            self.completionHandler = nil;
        }
        self.currentNavigation = nil;
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    if (navigation == self.currentNavigation) {
        if (self.completionHandler != nil) {
            self.completionHandler(error);
            self.completionHandler = nil;
        }
        self.currentNavigation = nil;
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    if (self.currentNavigation != nil) {
        if (self.completionHandler != nil) {
            self.completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUWebKitTerminationError userInfo:nil]);
            self.completionHandler = nil;
        }
        
        self.currentNavigation = nil;
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURLRequest *request = navigationAction.request;
    NSURL *requestURL = request.URL;
    BOOL isAboutBlank = NO;
    BOOL safeURL = SUWebViewIsSafeURL(requestURL, &isAboutBlank);
    
    // Do not allow redirects to dangerous protocols such as file://
    if (!safeURL) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", requestURL.scheme);
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        // Ensure we're finished loading
        if (self.completionHandler == nil) {
            if (!isAboutBlank) {
                [[NSWorkspace sharedWorkspace] openURL:requestURL];
            }
            
            decisionHandler(WKNavigationActionPolicyCancel);
        } else {
            decisionHandler(WKNavigationActionPolicyAllow);
        }
    }
}

@end

#endif
