//
//  SUGlobalUpdateLock.h
//  Sparkle
//
//  Created by Bibhas Acharya on 7/12/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#ifndef SUGLOBALUPDATELOCK_H
#define SUGLOBALUPDATELOCK_H

#if __has_feature(modules)
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

@interface SUGlobalUpdateLock : NSObject

+ (SUGlobalUpdateLock *)sharedLock;
- (void)lock;
- (void)unlock;

@end

#endif
