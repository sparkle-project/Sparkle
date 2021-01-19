//
//  SULegacyWebView.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#import "SULegacyWebView.h"
#import "SUWebViewCommon.h"
#import "SULog.h"
#import <WebKit/WebKit.h>

// WebKit protocols are not explicitly declared until 10.11 SDK, so
// declare dummy protocols to keep the build working on earlier SDKs.
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101100
@protocol WebFrameLoadDelegate <NSObject>
@end
@protocol WebPolicyDelegate <NSObject>
@end
@protocol WebUIDelegate <NSObject>
@end
#endif

@interface SULegacyWebView () <WebPolicyDelegate, WebFrameLoadDelegate, WebUIDelegate>

@property (nonatomic, readonly) WebView *webView;
@property (nonatomic) void (^completionHandler)(NSError * _Nullable);

@end

@implementation SULegacyWebView

@synthesize webView = _webView;
@synthesize completionHandler = _completionHandler;

- (instancetype)initWithColorStyleSheetLocation:(NSURL *)colorStyleSheetLocation fontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize javaScriptEnabled:(BOOL)javaScriptEnabled
{
    self = [super init];
    if (self != nil) {
        _webView = [[WebView alloc] initWithFrame:NSZeroRect];
        
        WebPreferences *preferences = _webView.preferences;
        preferences.javaScriptEnabled = javaScriptEnabled;
        preferences.javaEnabled = NO;
        preferences.plugInsEnabled = NO;
        
        // Mimicking settings when WebView used to be in SUUpdateAlert nib
        preferences.loadsImagesAutomatically = YES;
        preferences.allowsAnimatedImages = YES;
        preferences.allowsAnimatedImageLooping = YES;
        
        // Settings for default style
        preferences.userStyleSheetEnabled = YES;
        preferences.userStyleSheetLocation = colorStyleSheetLocation;
        preferences.standardFontFamily = fontFamily;
        preferences.defaultFontSize = fontPointSize;
        
        _webView.preferences = preferences;
        _webView.policyDelegate = self;
        _webView.frameLoadDelegate = self;
        _webView.UIDelegate = self;
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
    [[self.webView mainFrame] loadHTMLString:htmlString baseURL:baseURL];
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    self.completionHandler = [completionHandler copy];
    [[self.webView mainFrame] loadData:data MIMEType:MIMEType textEncodingName:textEncodingName baseURL:baseURL];
}

- (void)loadRequest:(NSURLRequest *)urlRequest completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    self.completionHandler = [completionHandler copy];
    [[self.webView mainFrame] loadRequest:urlRequest];
}

- (void)stopLoading
{
    self.completionHandler = nil;
    [self.webView stopLoading:self];
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
    self.webView.drawsBackground = drawsBackground;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if ([frame parentFrame] == nil) {
        if (self.completionHandler != nil) {
            self.completionHandler(nil);
            self.completionHandler = nil;
        }
        [sender display]; // necessary to prevent weird scroll bar artifacting
    }
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if ([frame parentFrame] == nil) {
        if (self.completionHandler != nil) {
            self.completionHandler(error);
            self.completionHandler = nil;
        }
    }
}

- (void)webView:(WebView *)__unused sender decidePolicyForNavigationAction:(NSDictionary *)__unused actionInformation request:(NSURLRequest *)request frame:(WebFrame *)__unused frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL *requestURL = request.URL;
    BOOL isAboutBlank = NO;
    BOOL safeURL = SUWebViewIsSafeURL(requestURL, &isAboutBlank);

    // Do not allow redirects to dangerous protocols such as file://
    if (!safeURL) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", requestURL.scheme);
        [listener ignore];
        return;
    }

    // Ensure we are finished loading
    if (self.completionHandler == nil) {
        if (requestURL && !isAboutBlank) {
            [[NSWorkspace sharedWorkspace] openURL:requestURL];
        }

        [listener ignore];
    }
    else {
        [listener use];
    }
}

// Clean up the contextual menu.
- (NSArray *)webView:(WebView *)__unused sender contextMenuItemsForElement:(NSDictionary *)__unused element defaultMenuItems:(NSArray *)defaultMenuItems
{
    NSMutableArray *webViewMenuItems = [defaultMenuItems mutableCopy];

    if (webViewMenuItems)
    {
        for (NSMenuItem *menuItem in defaultMenuItems)
        {
            NSInteger tag = [menuItem tag];

            switch (tag)
            {
                case WebMenuItemTagOpenLinkInNewWindow:
                case WebMenuItemTagDownloadLinkToDisk:
                case WebMenuItemTagOpenImageInNewWindow:
                case WebMenuItemTagDownloadImageToDisk:
                case WebMenuItemTagOpenFrameInNewWindow:
                case WebMenuItemTagGoBack:
                case WebMenuItemTagGoForward:
                case WebMenuItemTagStop:
                case WebMenuItemTagReload:
                    [webViewMenuItems removeObjectIdenticalTo:menuItem];
            }
        }
    }

    return webViewMenuItems;
}

@end
