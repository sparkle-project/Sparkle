//
//  SULocalizations.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SULocalizations_h
#define SULocalizations_h

#import "SUConstants.h"

#define SULocalizedStringFromTableInBundle(key, tbl, bundle, comment) NSLocalizedStringFromTableInBundle(key, tbl, bundle, comment)

#define SULocalizedString(key, comment) SULocalizedStringFromTableInBundle(key, @"Sparkle", (NSBundle * _Nonnull)([NSBundle bundleWithIdentifier:SUBundleIdentifier] ? [NSBundle bundleWithIdentifier:SUBundleIdentifier] : [NSBundle mainBundle]), comment)

#endif /* SULocalizations_h */
