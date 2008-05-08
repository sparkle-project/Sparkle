//
//  SUPlainInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUPLAININSTALLER_H
#define SUPLAININSTALLER_H

#import "Sparkle.h"

@interface SUPlainInstaller : SUInstaller { }
+ (void)performInstallationWithPath:(NSString *)path hostBundle:(NSBundle *)hostBundle delegate:delegate synchronously:(BOOL)synchronously;
@end

#endif
