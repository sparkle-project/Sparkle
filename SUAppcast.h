//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class RSS, SUAppcastItem, SUUtilities;
@interface SUAppcast : NSObject {
	NSArray *items;
	id delegate;
	SUUtilities *utilities;
}

- (id)initWithUtilities:(SUUtilities *)aUtility;

- (void)fetchAppcastFromURL:(NSURL *)url;
- (void)setDelegate:delegate;

- (SUAppcastItem *)newestItem;
- (NSArray *)items;

@end

@interface NSObject (SUAppcastDelegate)
- (void)appcastDidFinishLoading:(SUAppcast *)appcast;
@end
