//
//  SUSystemProfiler.h
//  Sparkle
//
//  Created by Andy Matuschak on 12/22/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#ifndef SUSYSTEMPROFILER_H
#define SUSYSTEMPROFILER_H

@interface SUSystemProfiler : NSObject {}
+ (SUSystemProfiler *)sharedSystemProfiler;
- (NSMutableArray *)systemProfileArrayForHostBundle:(NSBundle *)hostBundle;
@end

#endif
