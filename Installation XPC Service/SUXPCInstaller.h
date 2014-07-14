//
//  SUXPCInstaller.h
//  Sparkle
//
//  Created by Whitney Young on 3/19/12.
//  Copyright (c) 2012 FadingRed. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface SUXPCInstaller : NSObject

+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst temporaryName:(NSString *)tmp error:(NSError **)outError;

+ (BOOL)copyPathContent:(NSString *)src toDirectory:(NSString *)dstDir error:(NSError **)outError; // dstDir will be created if absent

+ (void)launchTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments completionHandler:(void (^)(void))completionHandler;

+ (void)launchTaskWithPath:(NSString *)launchPath
                 arguments:(NSArray *)arguments
               environment:(NSDictionary *)environment
      currentDirectoryPath:(NSString *)currentDirPath
                 inputData:(NSData *)inputData
         waitForTaskResult:(BOOL)waitForTaskResult
             waitUntilDone:(BOOL)waitUntilDone // for sync/async logic
         completionHandler:(void (^)(int result, NSData *outputData))completionHandler;

@end
