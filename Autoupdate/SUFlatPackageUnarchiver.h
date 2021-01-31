//
//  SUFlatPackageUnarchiver.h
//  Autoupdate
//
//  Created by Mayur Pawashe on 1/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// An unarchiver for flat packages that doesn't really do any unarchiving
@interface SUFlatPackageUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithFlatPackagePath:(NSString *)flatPackagePath expectingInstallationType:(NSString *)installationType;

@end

NS_ASSUME_NONNULL_END
