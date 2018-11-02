//
//  SUAdHocCodeSigning.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SUAdHocCodeSigning : NSObject

+ (BOOL)codeSignApplicationAtPath:(NSString *)applicationPath;

@end
