//
//  SUUpdatePermissionPromptResult.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SUCheckUpdatesChoice) {
    SUAutomaticallyCheck,
    SUDoNotAutomaticallyCheck
};

@interface SUUpdatePermissionPromptResult : NSObject<NSSecureCoding>

+ (instancetype)updatePermissionPromptResultWithChoice:(SUCheckUpdatesChoice)choice shouldSendProfile:(BOOL)shouldSendProfile;

@property (nonatomic, readonly) SUCheckUpdatesChoice choice;
@property (nonatomic, readonly) BOOL shouldSendProfile;

@end
