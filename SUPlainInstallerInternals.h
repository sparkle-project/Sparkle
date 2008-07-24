//
//  SUPlainInstallerInternals.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUPLAININSTALLERINTERNALS_H
#define SUPLAININSTALLERINTERNALS_H

#import "SUPlainInstaller.h"

@interface SUPlainInstaller (Internals)
+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst error:(NSError **)error;
@end

#endif
