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
#import "SUInstaller.h"

@interface SUPlainInstaller : SUInstaller { }
+ (void)performInstallationWithPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously;
@end

#endif
