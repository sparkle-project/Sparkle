//
//  SUExportedConstants.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/27/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#ifndef SUExportedConstants_h
#define SUExportedConstants_h

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

#import <Sparkle/SUExport.h>

SU_EXPORT extern NSString *const SUAppcastElementBetaChannel;

#endif /* SUExportedConstants_h */
