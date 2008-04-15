//
//  SUPackageInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUPlainInstaller.h"

@interface SUPackageInstaller : SUPlainInstaller { }
+ (void)installPath:(NSString *)path overHostBundle:(NSBundle *)bundle delegate:delegate;
@end
