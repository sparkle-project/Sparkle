//
//  SUUpdater_Private.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/9/11.
//  Copyright 2011 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"
#import "SUCodeSigningVerifier.h"
#import "SUBasicUpdateDriver.h"

@interface SUUpdater (Private)

- (BOOL)mayUpdateAndRestart;
- (SUHost *)host;
- (SUBasicUpdateDriver *)driver;

@end

@interface NSObject (SUPrivateUpdaterDelegateInformalProtocol)

- (void)updaterWillStartUpdateProcess:(SUUpdater *)updater;
- (void)updaterDidEndUpdateProcess:(SUUpdater *)updater;

@end
