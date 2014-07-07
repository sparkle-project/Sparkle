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
+ (NSString *)temporaryNameForPath:(NSString *)path;
+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst temporaryName:(NSString *)tmp error:(NSError **)error;
+ (void)_movePathToTrash:(NSString *)path;
+ (BOOL)_removeFileAtPath:(NSString *)path error:(NSError **)error;
+ (BOOL)_removeFileAtPathWithForcedAuthentication:(NSString *)src error:(NSError **)error;
@end

#endif
