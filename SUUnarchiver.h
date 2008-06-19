//
//  SUUnarchiver.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUNARCHIVER_H
#define SUUNARCHIVER_H

@interface SUUnarchiver : NSObject {
	id delegate;
	NSURL *archiveURL;
}

+ (SUUnarchiver *)unarchiverForURL:(NSURL *)URL;
- (void)setDelegate:delegate;

- (void)start;

@end

@interface NSObject (SUUnarchiverDelegate)
- (void)unarchiver:(SUUnarchiver *)unarchiver extractedLength:(long)length;
- (void)unarchiverDidFinish:(SUUnarchiver *)unarchiver;
- (void)unarchiverDidFail:(SUUnarchiver *)unarchiver;
@end

#endif
