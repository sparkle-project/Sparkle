//
//  SUPlainInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"

@interface SUPlainInstaller : SUInstaller { }
+ (void)installPath:(NSString *)path overHostBundle:(NSBundle *)bundle delegate:delegate;
@end
