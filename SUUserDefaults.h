//
//  SUUserDefaults.h
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#ifndef SUUSERDEFAULTS_H
#define SUUSERDEFAULTS_H

/*!
    @class
    @abstract    A substitute for NSUserDefaults that will work with arbitrary bundle identifiers.
    @discussion  Make sure you call -setIdentifier: before using SUUserDefaults. The other methods in this class work just like those in NSUserDefaults.
*/

@interface SUUserDefaults : NSObject {
	NSString *identifier;
}

/*!
    @method     
    @abstract   Returns a singleton instance of the user defaults class.
*/
+ (SUUserDefaults *)standardUserDefaults;

/*!
    @method     
    @abstract   Sets which bundle identifier to use when setting and retrieving defaults.
    @discussion It is imperative that you set the identifier through this method before trying to set or retrieve defaults.
*/
- (void)setIdentifier:(NSString *)identifier;

- (id)objectForKey:(NSString *)defaultName;
- (void)setObject:(id)value forKey:(NSString *)defaultName;
- (BOOL)boolForKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;
@end

#endif
