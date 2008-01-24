//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

@class RSS, SUAppcastItem;
@interface SUAppcast : NSObject {
	NSArray *items;
	id delegate;
}

- (void)fetchAppcastFromURL:(NSURL *)url parameters:(NSArray *)parameters;
- (void)setDelegate:delegate;

- (SUAppcastItem *)newestItem;
- (NSArray *)items;

@end

@interface NSObject (SUAppcastDelegate)
- (void)appcastDidFinishLoading:(SUAppcast *)appcast;
- (void)appcastDidFailToLoad:(SUAppcast *)appcast;
- (NSString *)userAgentForAppcast:(SUAppcast *)appcast;
@end

#endif
