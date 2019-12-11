//
//  SPUURLRequest.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/19/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUURLRequest.h"

#import "SUOperatingSystem.h"

#include "AppKitPrevention.h"

static NSString *SPUURLRequestURLKey = @"SPUURLRequestURL";
static NSString *SPUURLRequestCachePolicyKey = @"SPUURLRequestCachePolicy";
static NSString *SPUURLRequestTimeoutIntervalKey = @"SPUURLRequestTimeoutInterval";
static NSString *SPUURLRequestHttpHeaderFieldsKey = @"SPUURLRequestHttpHeaderFields";
static NSString *SPUURLRequestNetworkServiceTypeKey = @"SPUURLRequestNetworkServiceType";

@interface SPUURLRequest ()

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSURLRequestCachePolicy cachePolicy;
@property (nonatomic, readonly) NSTimeInterval timeoutInterval;
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *httpHeaderFields;
@property (nonatomic, readonly) NSURLRequestNetworkServiceType networkServiceType;

@end

@implementation SPUURLRequest

@synthesize url = _url;
@synthesize cachePolicy = _cachePolicy;
@synthesize timeoutInterval = _timeoutInterval;
@synthesize httpHeaderFields = _httpHeaderFields;
@synthesize networkServiceType = _networkServiceType;

- (instancetype)initWithURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)cachePolicy timeoutInterval:(NSTimeInterval)timeoutInterval httpHeaderFields:(NSDictionary<NSString *, NSString *> *)httpHeaderFields networkServiceType:(NSURLRequestNetworkServiceType)networkServiceType
{
    self = [super init];
    if (self != nil) {
        _url = url;
        _cachePolicy = cachePolicy;
        _timeoutInterval = timeoutInterval;
        _httpHeaderFields = httpHeaderFields;
        _networkServiceType = networkServiceType;
    }
    return self;
}

+ (instancetype)URLRequestWithRequest:(NSURLRequest *)request
{
    return [(SPUURLRequest *)[[self class] alloc] initWithURL:request.URL cachePolicy:request.cachePolicy timeoutInterval:request.timeoutInterval httpHeaderFields:request.allHTTPHeaderFields networkServiceType:request.networkServiceType];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.url forKey:SPUURLRequestURLKey];
    [coder encodeInteger:(NSInteger)self.cachePolicy forKey:SPUURLRequestCachePolicyKey];
    [coder encodeDouble:self.timeoutInterval forKey:SPUURLRequestTimeoutIntervalKey];
    [coder encodeInteger:(NSInteger)self.networkServiceType forKey:SPUURLRequestNetworkServiceTypeKey];
    
    if (self.httpHeaderFields != nil) {
        [coder encodeObject:self.httpHeaderFields forKey:SPUURLRequestHttpHeaderFieldsKey];
    }
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    if (SUAVAILABLE(10, 8)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        NSURL *url = [decoder decodeObjectOfClass:[NSURL class] forKey:SPUURLRequestURLKey];
        NSURLRequestCachePolicy cachePolicy = (NSURLRequestCachePolicy)[decoder decodeIntegerForKey:SPUURLRequestCachePolicyKey];
        NSTimeInterval timeoutInterval = [decoder decodeDoubleForKey:SPUURLRequestTimeoutIntervalKey];
        NSDictionary<NSString *, NSString *> *httpHeaderFields = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSDictionary class], [NSString class]]] forKey:SPUURLRequestHttpHeaderFieldsKey];
#pragma clang diagnostic pop
        NSURLRequestNetworkServiceType networkServiceType = (NSURLRequestNetworkServiceType)[decoder decodeIntegerForKey:SPUURLRequestNetworkServiceTypeKey];

        return [self initWithURL:url cachePolicy:cachePolicy timeoutInterval:timeoutInterval httpHeaderFields:httpHeaderFields networkServiceType:networkServiceType];
    } else {
        abort(); // Not used on 10.7
    }
}

- (NSURLRequest *)request
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url cachePolicy:self.cachePolicy timeoutInterval:self.timeoutInterval];
    if (self.httpHeaderFields != nil) {
        request.allHTTPHeaderFields = self.httpHeaderFields;
    }
    request.networkServiceType = self.networkServiceType;
    return [request copy];
}

@end
