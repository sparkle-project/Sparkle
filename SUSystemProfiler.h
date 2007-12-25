//
//  SUSystemProfiler.h
//  Sparkle
//
//  Created by Andy Matuschak on 12/22/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#ifndef SUSYSTEMPROFILER_H
#define SUSYSTEMPROFILER_H

@interface SUSystemProfiler : NSObject {}
+ (NSURL *)profiledURLForAppcastURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hostBundle;
@end

#endif