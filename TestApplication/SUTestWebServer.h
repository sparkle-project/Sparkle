//
//  SUTestWebServer.h
//  Sparkle
//
//  Created by Kevin Wojniak on 10/8/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

__attribute__((objc_direct_members)) @interface SUTestWebServer : NSObject

- (instancetype)initWithPort:(int)port workingDirectory:(NSString*)workingDirectory;

- (void)close;

@end
