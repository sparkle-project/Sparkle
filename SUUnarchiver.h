//
//  SUUnarchiver.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUNARCHIVER_H
#define SUUNARCHIVER_H

@class SUHost;
@protocol SUUnarchiverDelegate;

@interface SUUnarchiver : NSObject {
	id<SUUnarchiverDelegate> delegate;
	NSString *archivePath;
	SUHost *updateHost;
}
@property (assign)id<SUUnarchiverDelegate> delegate;

+ (SUUnarchiver *)unarchiverForPath:(NSString *)path updatingHost:(SUHost *)host;

- (void)start;
@end

@protocol SUUnarchiverDelegate <NSObject>
- (void)unarchiver:(SUUnarchiver *)unarchiver extractedLength:(unsigned long)length;
- (void)unarchiverDidFinish:(SUUnarchiver *)unarchiver;
- (void)unarchiverDidFail:(SUUnarchiver *)unarchiver;
- (void)unarchiver:(SUUnarchiver *)unarchiver requiresPasswordReturnedViaInvocation:(NSInvocation *)invocation;
@end

#endif
