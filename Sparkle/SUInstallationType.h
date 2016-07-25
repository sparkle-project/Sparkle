//
//  SUInstallationType.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SUInstallationType_h
#define SUInstallationType_h

#define SUInstallationTypeApplication @"application" // the default installation type for ordinary application updates
#define SUInstallationTypeGuidedPackage @"guided-package" // the preferred installation type for package installations
#define SUInstallationTypePackage @"package" // the deprecated installation type; use guided package instead

#define SUInstallationTypeDefault SUInstallationTypeApplication
#define SUInstallationTypesArray (@[SUInstallationTypeApplication, SUInstallationTypeGuidedPackage, SUInstallationTypePackage])
#define SUValidInstallationType(x) ((x != nil) && [SUInstallationTypesArray containsObject:x])

#endif /* SUInstallationType_h */
