//
//  SUTouchBarForwardDeclarations.h
//  Sparkle
//
//  Created by Yuxin Wang on 18/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

// Once Sparkle no longer supports OSX 10.12.0, this file can be deleted.

#import <Foundation/Foundation.h>

// When compiling against the 10.12.1 SDK or later, just provide forward
// declarations to suppress the partial availability warnings.

@class NSTouchBar;
@protocol NSTouchBarDelegate;
@class NSTouchBarItem;
@class NSCustomTouchBarItem;

#endif
