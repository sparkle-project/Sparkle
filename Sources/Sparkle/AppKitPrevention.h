//
//  AppKitPrevention.h
//  Sparkle
//
//  Created by Mayur Pawashe on 1/17/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

// #include (not #import) this header to prevent AppKit from being imported
// Note this should be your LAST #include in your implementation file

// If this error is triggered, you can have Xcode indicate to you which source file including this header caused the issue

// One may wonder for certain targets where AppKit is banned completely, why just not link AppKit instead.
// Well, Xcode has thing called auto-linking that I don't trust very much.
// Even after trying to disable the setting, I've had targets able to link to AppKit without AppKit being specified in the list of linked libraries.

#ifdef _APPKITDEFINES_H
#error This is a core or daemon-safe module and should NOT import AppKit
#endif
