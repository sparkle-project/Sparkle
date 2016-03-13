//
//  SUInstallerProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUInstaller <NSObject>

- (BOOL)performFirstStage:(NSError **)error;

- (BOOL)performSecondStageAllowingUI:(BOOL)allowsUI error:(NSError **)error;

- (BOOL)performThirdStage:(NSError **)error;

- (void)cleanup;

@end
