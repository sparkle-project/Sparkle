//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

@class SUAppcastItem;
@interface SUAppcast : NSObject
{
@private
	NSArray *items;
    NSMutableDictionary *appcastValues;
	id delegate;
	NSString *downloadFilename;
	NSURLDownload *download;
}

- (void)fetchAppcastFromURL:(NSURL *)url;
- (void)setDelegate:(id)delegate;
- (void)setUserAgentString:(NSString *)userAgentString;
- (void)setAppcastValue:(NSString *)value forKey:(NSString *)key;
- (void)setAllAppcastValues:(NSDictionary *)inAppcastValues;

- (NSArray *)items;

@end

@interface NSObject (SUAppcastDelegate)
- (void)appcast:(SUAppcast *)appcast willFetchURLRequest:(NSMutableURLRequest *)request;
- (void)appcastDidFinishLoading:(SUAppcast *)appcast;
- (void)appcast:(SUAppcast *)appcast failedToLoadWithError:(NSError *)error;
@end

#endif
