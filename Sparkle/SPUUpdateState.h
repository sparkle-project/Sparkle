//
//  SPUUpdateState.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/29/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SPUUpdateState_h
#define SPUUpdateState_h

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPUUpdateStage) {
    SPUUpdateStageNotDownloaded,
    SPUUpdateStageDownloaded,
    SPUUpdateStageInstalling,
    SPUUpdateStageInformational
};

SU_EXPORT @interface SPUUpdateState : NSObject

@property (nonatomic, readonly) SPUUpdateStage stage;
@property (nonatomic, readonly) BOOL userInitiated;
@property (nonatomic, readonly) BOOL majorUpgrade;
@property (nonatomic, readonly) BOOL criticalUpdate;

@end

NS_ASSUME_NONNULL_END

#endif /* SPUUpdateState_h */
