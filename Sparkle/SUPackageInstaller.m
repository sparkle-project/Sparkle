//
//  SUPackageInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPackageInstaller.h"
#import "SUVersionComparisonProtocol.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUErrors.h"
#import "SULog.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUPackageInstaller ()

@property (nonatomic, readonly, copy) NSString *packagePath;

@end

@implementation SUPackageInstaller

@synthesize packagePath = _packagePath;

- (instancetype)initWithHost:(SUHost *)__unused host sourcePath:(NSString *)sourcePath installationPath:(NSString *)__unused installationPath versionComparator:(id <SUVersionComparison>)__unused comparator
{
    self = [super init];
    if (self != nil) {
        _packagePath = [sourcePath copy];
    }
    return self;
}

- (BOOL)startInstallation:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)resumeInstallation:(NSError * __autoreleasing *)error
{
    // Run installer using the "open" command to ensure it is launched in front of current application.
    // -W = wait until the app has quit.
    // -n = Open another instance if already open.
    // -b = app bundle identifier
    NSString *command = @"/usr/bin/open";
    NSArray *args = @[@"-W", @"-n", @"-b", @"com.apple.installer", self.packagePath];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:command]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find Apple's installer tool!" }];
        }
        
        return NO;
    }
    
    // Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
    @try {
        NSTask *installer = [NSTask launchedTaskWithLaunchPath:command arguments:args];
        [installer waitUntilExit];
    }
    @catch (NSException *exception) {
        SULog(@"Error: Failed to launch package installer: %@", exception);
    }
    
    return YES;
}

- (void)cleanup
{
}

@end
