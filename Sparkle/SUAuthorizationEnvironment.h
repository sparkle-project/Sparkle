//
//  SUAuthorizationEnvironment.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/27/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A class used for specifying an environment for an authorization request.
 * This includes a prompt message and an icon image that may show up on an authorization dialog
 */
@interface SUAuthorizationEnvironment : NSObject

/**
 * Creates an authorization environment
 *
 * @param prompt A message that will show up in the authorization prompt dialog. The system may append a message
 * to this prompt. i.e, something like "Enter your password to allow changes." Supply empty string if the prompt is not important.
 *
 * @param iconPath A path to a icon on disk that will be used as the icon that shows up in the authorization dialog.
 * This should be a PNG image that is 32x32 in dimension. It should also be a path that is readable from anybody,
 * likely in a temporary directory.
 *
 * @return A new authorization environment instance
 */
- (instancetype)initWithPrompt:(NSString *)prompt iconPath:(NSString *)iconPath;

/**
 * Retrieve the authorization environment struct that can be used for the Authorization Service APIs
 *
 * @return A authorization environment reference. Because this returns an internal pointer, this may only be valid as long as this object instance is alive.
 */
@property (nonatomic, readonly) AuthorizationEnvironment *environment NS_RETURNS_INNER_POINTER;

@end

NS_ASSUME_NONNULL_END
