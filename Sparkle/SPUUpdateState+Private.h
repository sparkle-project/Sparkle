//
//  SPUUpdateState+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/9/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#ifndef SPUUpdateState_Private_h
#define SPUUpdateState_Private_h

NS_ASSUME_NONNULL_BEGIN

@interface SPUUpdateState (Private)

- (instancetype)initWithStage:(SPUUpdateStage)stage userInitiated:(BOOL)userInitiated;

@end

NS_ASSUME_NONNULL_END

#endif /* SPUUpdateState_Private_h */
