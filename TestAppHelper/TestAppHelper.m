//
//  TestAppHelper.m
//  TestAppHelper
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "TestAppHelper.h"
#import "SUAdHocCodeSigning.h"

@implementation TestAppHelper

- (void)codeSignApplicationAtPath:(NSString *)applicationPath reply:(void (^)(BOOL))reply
{
    reply([SUAdHocCodeSigning codeSignApplicationAtPath:applicationPath]);
}

@end
