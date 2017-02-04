//
//  SUNoOpUnarchiver.h
//  Sparkle
//
//  Created by Andoni Morales Alastruey on 4/2/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#ifndef SUNoOpUnarchiver_h
#define SUNoOpUnarchiver_h

#import <Foundation/Foundation.h>
#import "SUUnarchiverProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUNoOpUnarchiver : NSObject <SUUnarchiverProtocol>

- (instancetype)initWithArchivePath:(NSString *)archivePath;
@end

NS_ASSUME_NONNULL_END


#endif /* SUNoOpUnarchiver_h */
