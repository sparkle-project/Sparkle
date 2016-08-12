//
//  TestAppHelperProtocol.h
//  TestAppHelper
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol TestAppHelperProtocol

- (void)codeSignApplicationAtPath:(NSString *)applicationPath reply:(void (^)(BOOL))reply;

@end
