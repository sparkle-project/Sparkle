//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//
// Additions by Yahoo:
// Copyright 2014 Yahoo Inc. Licensed under the project's open source license.
//
// JSON format appcasts
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

@protocol SUAppcastDelegate;

@class SUAppcastItem;
@interface SUAppcast : NSObject<NSURLDownloadDelegate>
{
@private
	NSArray *items;
	NSString *userAgentString;
	id<SUAppcastDelegate> delegate;
	NSString *downloadFilename;
	NSURLDownload *download;
    bool            useJSON;    
}


@property (assign) id<SUAppcastDelegate> delegate;
@property (copy) NSString *userAgentString;

- (void)fetchAppcastFromURL:(NSURL *)url;
- (NSArray *)items;
- (void)setUseJSON:(bool)val;

@end

@protocol SUAppcastDelegate <NSObject>
- (void)appcastDidFinishLoading:(SUAppcast *)appcast;
- (void)appcast:(SUAppcast *)appcast failedToLoadWithError:(NSError *)error;
@end

#endif
