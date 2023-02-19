//
//  SUVersionDisplayProtocol.h
//  EyeTV
//
//  Created by Uli Kusterer on 08.12.09.
//  Copyright 2009 Elgato Systems GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>

#if defined(BUILDING_SPARKLE_SOURCES_EXTERNALLY)
// Ignore incorrect warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#import "SUExport.h"
#pragma clang diagnostic pop
#else
#import <Sparkle/SUExport.h>
#endif

@class SUAppcastItem;

NS_ASSUME_NONNULL_BEGIN

/**
    Applies special display formatting to version numbers.
*/
SU_EXPORT @protocol SUVersionDisplay <NSObject>

- (NSString *)formatUpdateDisplayVersionFromUpdate:(SUAppcastItem *)update andBundleDisplayVersion:(NSString * _Nonnull __autoreleasing * _Nonnull)inOutBundleDisplayVersion withBundleVersion:(NSString *)bundleVersion;

@optional

/**
 Formats two version strings.
 
 Both versions are provided so that important distinguishing information
 can be displayed while also leaving out unnecessary/confusing parts.
*/
- (void)formatVersion:(NSString *_Nonnull*_Nonnull)inOutVersionA andVersion:(NSString *_Nonnull*_Nonnull)inOutVersionB __deprecated_msg("Please use -formatUpdateDisplayVersionFromUpdate:andBundleDisplayVersion:withBundleVersion:");

@end

NS_ASSUME_NONNULL_END
