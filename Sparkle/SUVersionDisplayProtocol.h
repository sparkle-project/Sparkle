//
//  SUVersionDisplayProtocol.h
//  EyeTV
//
//  Created by Uli Kusterer on 08.12.09.
//  Copyright 2009 Elgato Systems GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>

#if defined(BUILDING_SPARKLE_TESTS)
#import "SUExport.h"
#else
#import <Sparkle/SUExport.h>
#endif

/**
    Applies special display formatting to version numbers.
*/
SU_EXPORT @protocol SUVersionDisplay

/**
    Formats two version strings.

    Both versions are provided so that important distinguishing information
    can be displayed while also leaving out unnecessary/confusing parts.
*/
- (void)formatVersion:(NSString *_Nonnull*_Nonnull)inOutVersionA andVersion:(NSString *_Nonnull*_Nonnull)inOutVersionB;

@end
