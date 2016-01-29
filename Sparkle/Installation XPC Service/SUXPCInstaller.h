//
//  SUXPCInstaller.h
//  Sparkle
//
//  Created by Whitney Young on 3/19/12.
//  Copyright (c) 2012 FadingRed. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface SUXPCInstaller : NSObject

//+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst appendVersion:(BOOL)appendVersion error:(NSError *__autoreleasing *)outError;

+ (BOOL)copyPathContent:(NSString *)src toDirectory:(NSString *)dstDir error:(NSError *__autoreleasing *)outError; // dstDir will be created if absent

+ (void)launchTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;

+ (void)launchTaskWithPath:(NSString *)launchPath
                 arguments:(NSArray *)arguments
               environment:(NSDictionary *)environment
      currentDirectoryPath:(NSString *)currentDirPath
                 inputData:(NSData *)inputData
             waitUntilDone:(BOOL)waitUntilDone
         completionHandler:(void (^)(int result, NSData *outputData))completionHandler;

@end

FOUNDATION_EXPORT BOOL SUShouldUseXPCInstaller(void);
