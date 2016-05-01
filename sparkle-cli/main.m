//
//  main.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Sparkle/Sparkle.h>
#import "SUCommandLineDriver.h"
#include <getopt.h>

#define APPLICATION_FLAG "application"
#define DEFER_FLAG "defer-install"
#define VERBOSE_FLAG "verbose"
#define CHECK_NOW_FLAG "check-immediately"
#define GRANT_AUTOMATIC_CHECKING_FLAG "grant-automatic-checks"
#define SEND_PROFILE_FLAG "send-profile"

static void printUsage(char **argv)
{
    fprintf(stderr, "Usage: %s <update-bundle-path> [--%s <path-to-application>] [--%s] [--%s] [--%s] [--%s] [--%s]\n", argv[0], APPLICATION_FLAG, CHECK_NOW_FLAG, GRANT_AUTOMATIC_CHECKING_FLAG, SEND_PROFILE_FLAG, DEFER_FLAG, VERBOSE_FLAG);
}

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        struct option longOptions[] = {
            {APPLICATION_FLAG, required_argument, NULL, 0},
            {DEFER_FLAG, no_argument, NULL, 0},
            {VERBOSE_FLAG, no_argument, NULL, 0},
            {CHECK_NOW_FLAG, no_argument, NULL, 0},
            {GRANT_AUTOMATIC_CHECKING_FLAG, no_argument, NULL, 0},
            {SEND_PROFILE_FLAG, no_argument, NULL, 0},
            {0, 0, 0, 0}
        };
        
        NSString *applicationPath = nil;
        BOOL deferInstall = NO;
        BOOL verbose = NO;
        BOOL checkForUpdatesNow = NO;
        BOOL grantAutomaticChecking = NO;
        BOOL sendProfile = NO;
        
        while (YES) {
            int optionIndex = 0;
            int choice = getopt_long(argc, argv, "", longOptions, &optionIndex);
            if (choice == -1) {
                break;
            }
            switch (choice) {
                case 0:
                    if (strcmp(APPLICATION_FLAG, longOptions[optionIndex].name) == 0) {
                        assert(optarg != NULL);
                        
                        applicationPath = [[NSString alloc] initWithUTF8String:optarg];
                        if (applicationPath == nil) {
                            printUsage(argv);
                            return EXIT_FAILURE;
                        }
                    } else if (strcmp(DEFER_FLAG, longOptions[optionIndex].name) == 0) {
                        deferInstall = YES;
                    } else if (strcmp(VERBOSE_FLAG, longOptions[optionIndex].name) == 0) {
                        verbose = YES;
                    } else if (strcmp(CHECK_NOW_FLAG, longOptions[optionIndex].name) == 0) {
                        checkForUpdatesNow = YES;
                    } else if (strcmp(GRANT_AUTOMATIC_CHECKING_FLAG, longOptions[optionIndex].name) == 0) {
                        grantAutomaticChecking = YES;
                    } else if (strcmp(SEND_PROFILE_FLAG, longOptions[optionIndex].name) == 0) {
                        sendProfile = YES;
                    }
                case ':':
                    break;
                case '?':
                    printUsage(argv);
                    return EXIT_FAILURE;
                default:
                    abort();
            }
        }
        
        if (optind >= argc) {
            printUsage(argv);
            return EXIT_FAILURE;
        }
        
        NSString *updatePath = [[NSString alloc] initWithUTF8String:argv[optind]];
        if (updatePath == nil) {
            printUsage(argv);
            return EXIT_FAILURE;
        }
        
        SUUpdatePermissionPromptResult *updatePermission = nil;
        if (grantAutomaticChecking) {
            updatePermission = [SUUpdatePermissionPromptResult  updatePermissionPromptResultWithChoice:SUAutomaticallyCheck shouldSendProfile:sendProfile];
        }
        
        SUCommandLineDriver *driver = [[SUCommandLineDriver alloc] initWithUpdateBundlePath:updatePath applicationBundlePath:applicationPath updatePermission:updatePermission deferInstallation:deferInstall verbose:verbose];
        if (driver == nil) {
            fprintf(stderr, "Error: Failed to initialize updater. Are the bundle paths provided valid?\n");
            printUsage(argv);
            return EXIT_FAILURE;
        }
        
        [driver runAndCheckForUpdatesNow:checkForUpdatesNow];
        [[NSRunLoop currentRunLoop] run];
    }
    
    return EXIT_SUCCESS;
}
