//
//  SPUStandardVersionDisplay.h
//  Sparkle
//
//  Created on 2/18/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUVersionDisplayProtocol.h"
#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

SU_EXPORT @interface SPUStandardVersionDisplay : NSObject <SUVersionDisplay>

+ (instancetype)standardVersionDisplay;

@end

NS_ASSUME_NONNULL_END
