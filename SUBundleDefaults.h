//
//  SUBundleDefaults.h
//  Sparkle
//
//  Created by Christopher Atlan on 07.11.07.
//  Copyright 2007 Christopher Atlan. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SUUtilities;
@interface SUBundleDefaults : NSObject {
	SUUtilities *utilities;
	NSString *applicationID;
}

- (id)initWithUtilitie:(SUUtilities *)theUtilities;

- (id)objectForKey:(NSString *)defaultName;
- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;

- (NSString *)stringForKey:(NSString *)defaultName;
- (NSArray *)arrayForKey:(NSString *)defaultName;
- (NSDictionary *)dictionaryForKey:(NSString *)defaultName;
- (NSData *)dataForKey:(NSString *)defaultName;
- (NSArray *)stringArrayForKey:(NSString *)defaultName;
/*
- (int)integerForKey:(NSString *)defaultName; 
- (float)floatForKey:(NSString *)defaultName; 
*/
- (BOOL)boolForKey:(NSString *)defaultName;  
/*
- (void)setInteger:(int)value forKey:(NSString *)defaultName;
- (void)setFloat:(float)value forKey:(NSString *)defaultName;
*/
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;

@end
