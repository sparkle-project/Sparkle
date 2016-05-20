//
//  SUURLRequest.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/19/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUURLRequest.h"

static NSString *SUURLRequestURLKey = @"SUURLRequestURL";
static NSString *SUURLRequestCachePolicyKey = @"SUURLRequestCachePolicy";
static NSString *SUURLRequestTimeoutIntervalKey = @"SUURLRequestTimeoutInterval";
static NSString *SUURLRequestHttpHeaderFieldsKey = @"SUURLRequestHttpHeaderFields";

@interface SUURLRequest ()

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSURLRequestCachePolicy cachePolicy;
@property (nonatomic, readonly) NSTimeInterval timeoutInterval;
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *httpHeaderFields;

@end

@implementation SUURLRequest

@synthesize url = _url;
@synthesize cachePolicy = _cachePolicy;
@synthesize timeoutInterval = _timeoutInterval;
@synthesize httpHeaderFields = _httpHeaderFields;

- (instancetype)initWithURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval httpHeaderFields:(NSDictionary<NSString *, NSString *> *)httpHeaderFields
{
    self = [super init];
    if (self != nil) {
        _url = url;
        _cachePolicy = cachePolicy;
        _timeoutInterval = timeoutInterval;
        _httpHeaderFields = httpHeaderFields;
    }
    return self;
}

+ (instancetype)URLRequestWithRequest:(NSURLRequest *)request
{
    return [[[self class] alloc] initWithURL:request.URL cachePolicy:request.cachePolicy timeoutInterval:request.timeoutInterval httpHeaderFields:request.allHTTPHeaderFields];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.url forKey:SUURLRequestURLKey];
    [coder encodeInteger:self.cachePolicy forKey:SUURLRequestCachePolicyKey];
    [coder encodeDouble:self.timeoutInterval forKey:SUURLRequestTimeoutIntervalKey];
    
    if (self.httpHeaderFields != nil) {
        [coder encodeObject:self.httpHeaderFields forKey:SUURLRequestHttpHeaderFieldsKey];
    }
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    NSURL *url = [decoder decodeObjectOfClass:[NSURL class] forKey:SUURLRequestURLKey];
    NSURLRequestCachePolicy cachePolicy = (NSURLRequestCachePolicy)[decoder decodeIntegerForKey:SUURLRequestCachePolicyKey];
    NSTimeInterval timeoutInterval = [decoder decodeDoubleForKey:SUURLRequestTimeoutIntervalKey];
    NSDictionary<NSString *, NSString *> *httpHeaderFields = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [NSString class]]] forKey:SUURLRequestHttpHeaderFieldsKey];
    
    return [self initWithURL:url cachePolicy:cachePolicy timeoutInterval:timeoutInterval httpHeaderFields:httpHeaderFields];
}

- (NSURLRequest *)request
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url cachePolicy:self.cachePolicy timeoutInterval:self.timeoutInterval];
    if (self.httpHeaderFields != nil) {
        request.allHTTPHeaderFields = self.httpHeaderFields;
    }
    return [request copy];
}

@end
