//
//  SUAuthorizationEnvironment.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/27/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUAuthorizationEnvironment.h"

@implementation SUAuthorizationEnvironment
{
    // Declare data here so we won't have to do more dynamic allocations
    char _prompt[1024];
    char _iconPath[PATH_MAX];
    AuthorizationItem _environmentItems[2];
    AuthorizationEnvironment _environment;
}

- (instancetype)initWithPrompt:(NSString *)prompt iconPath:(NSString *)iconPath
{
    self = [super init];
    if (self != nil) {
        if (![prompt getFileSystemRepresentation:_prompt maxLength:sizeof(_prompt)]) {
            bzero(_prompt, sizeof(_prompt));
        }
        
        if (![iconPath getFileSystemRepresentation:_iconPath maxLength:sizeof(_iconPath)]) {
            bzero(_iconPath, sizeof(_iconPath));
        }
        
        _environmentItems[0] = (AuthorizationItem){.name = kAuthorizationEnvironmentPrompt, .valueLength = strlen(_prompt), .value = _prompt, .flags = 0};
        _environmentItems[1] = (AuthorizationItem){.name = kAuthorizationEnvironmentIcon, .valueLength = strlen(_iconPath), .value = _iconPath, .flags = 0};
        
        _environment = (AuthorizationEnvironment){.count = sizeof(_environmentItems) / sizeof(*_environmentItems), .items = _environmentItems};
    }
    return self;
}

- (AuthorizationEnvironment *)environment NS_RETURNS_INNER_POINTER
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    return &_environment;
#pragma clang diagnostic pop
}

@end
