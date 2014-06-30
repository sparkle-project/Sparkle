//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

@protocol SUAppcastDelegate;
@class SUAppcastItem;

@interface SUAppcast : NSObject <NSURLDownloadDelegate>
{
@private
    NSArray *items;
    NSString *userAgentString;
    id<SUAppcastDelegate> delegate;
    NSString *downloadFilename;
    NSURLDownload *download;
}

@property (assign) id<SUAppcastDelegate> delegate;
@property (copy) NSString *userAgentString;
@property (readonly, copy) NSArray *items;

- (void)fetchAppcastFromURL:(NSURL *)url;

@end

@protocol SUAppcastDelegate <NSObject>

- (void)appcastDidFinishLoading:(SUAppcast *)appcast;
- (void)appcast:(SUAppcast *)appcast failedToLoadWithError:(NSError *)error;

@end

#endif
