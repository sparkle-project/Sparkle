//
//  main.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SparkleCore/SparkleCore.h>
#import "SPUCommandLineDriver.h"
#include <getopt.h>

#define APPLICATION_FLAG "application"
#define DEFER_FLAG "defer-install"
#define VERBOSE_FLAG "verbose"
#define CHECK_NOW_FLAG "check-immediately"
#define GRANT_AUTOMATIC_CHECKING_FLAG "grant-automatic-checks"
#define SEND_PROFILE_FLAG "send-profile"
#define PROBE_FLAG "probe"
#define INTERACTIVE_FLAG "interactive"
#define FEED_URL_FLAG "feed-url"

static void printUsage(char **argv)
{
    fprintf(stderr, "Usage: %s bundle [--%s <app-path>] [--%s] [--%s] [--%s] [--%s] [--%s] [--%s] [--%s]\n", argv[0], APPLICATION_FLAG, CHECK_NOW_FLAG, PROBE_FLAG, GRANT_AUTOMATIC_CHECKING_FLAG, SEND_PROFILE_FLAG, DEFER_FLAG, INTERACTIVE_FLAG, VERBOSE_FLAG);
    fprintf(stderr, "Description:\n");
    fprintf(stderr, "  Check if any new updates for a Sparkle supported bundle need to be installed.\n\n");
    fprintf(stderr, "  If any new updates need to be installed, the user application\n  is terminated and the update is installed immediately unless --%s\n  is specified. If the application was alive, then it will be relaunched after.\n\n", DEFER_FLAG);
    fprintf(stderr, "  To check if an update is available without installing, use --%s.\n\n", PROBE_FLAG);
    fprintf(stderr, "  if no updates are available now, or if the last update check was recently\n  (unless --%s is specified) then nothing is done.\n\n", CHECK_NOW_FLAG);
    fprintf(stderr, "  If update permission is requested and --%s is not\n  specified, then checking for updates is aborted.\n\n", GRANT_AUTOMATIC_CHECKING_FLAG);
    fprintf(stderr, "  Unless --%s is specified, this tool will not request for escalated\n  authorization. Running as root is not supported.\n\n", INTERACTIVE_FLAG);
    fprintf(stderr, "  If --%s is specified, this tool will exit leaving a spawned process\n  for finishing the installation after the target application terminates.\n", DEFER_FLAG);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, " --%s\n    Path to the application to watch for termination and to relaunch.\n    If not provided, this is assumed to be the same as the bundle.\n", APPLICATION_FLAG);
    fprintf(stderr, " --%s\n    Immediately checks for updates to install.\n    Without this, updates are checked only when needed on a scheduled basis.\n", CHECK_NOW_FLAG);
    fprintf(stderr, " --%s\n    Probe for updates. Check if any updates are available but do not install.\n    An exit status of 0 is returned if a new update is available.\n", PROBE_FLAG);
    fprintf(stderr, " --%s\n    URL for appcast feed. This URL will be used for the feed instead of the one\n    in the bundle's Info.plist or in the bundle's user defaults.\n", FEED_URL_FLAG);
    fprintf(stderr, " --%s\n    Allows prompting the user for an authorization dialog prompt if the\n    installer needs elevated privileges, or allows performing an interactive\n    installer package.\n", INTERACTIVE_FLAG);
    fprintf(stderr, " --%s\n    If update permission is requested, this enables automatic update checks.\n    Note that this behavior may overwrite the user's defaults for the bundle.\n    This option has no effect if --%s is passed, or if the\n    user has replied to this request already, or if the developer configured\n    to skip it.\n", GRANT_AUTOMATIC_CHECKING_FLAG, CHECK_NOW_FLAG);
    fprintf(stderr, " --%s\n    Choose to send system profile information if update permission is requested.\n    This option can only take effect if --%s is passed.\n", SEND_PROFILE_FLAG, GRANT_AUTOMATIC_CHECKING_FLAG);
    fprintf(stderr, " --%s\n    Defer installation until after the application terminates on its own. The\n    application will not be relaunched unless the installation is resumed later.\n", DEFER_FLAG);
    fprintf(stderr, " --%s\n    Enable verbose logging.\n", VERBOSE_FLAG);
}

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        if (geteuid() == 0) {
            fprintf(stderr, "Error: Running as root is not supported\n");
            return EXIT_FAILURE;
        }
        
        struct option longOptions[] = {
            {APPLICATION_FLAG, required_argument, NULL, 0},
            {FEED_URL_FLAG, required_argument, NULL, 0},
            {DEFER_FLAG, no_argument, NULL, 0},
            {VERBOSE_FLAG, no_argument, NULL, 0},
            {CHECK_NOW_FLAG, no_argument, NULL, 0},
            {GRANT_AUTOMATIC_CHECKING_FLAG, no_argument, NULL, 0},
            {SEND_PROFILE_FLAG, no_argument, NULL, 0},
            {PROBE_FLAG, no_argument, NULL, 0},
            {INTERACTIVE_FLAG, no_argument, NULL, 0},
            {0, 0, 0, 0}
        };
        
        NSString *applicationPath = nil;
        NSString *feedURL = nil;
        BOOL deferInstall = NO;
        BOOL verbose = NO;
        BOOL checkForUpdatesNow = NO;
        BOOL grantAutomaticChecking = NO;
        BOOL sendProfile = NO;
        BOOL probeForUpdates = NO;
        BOOL interactive = NO;
        
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
                    } else if (strcmp(FEED_URL_FLAG, longOptions[optionIndex].name) == 0) {
                        assert(optarg != NULL);
                        
                        feedURL = [[NSString alloc] initWithUTF8String:optarg];
                        if (feedURL == nil) {
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
                    } else if (strcmp(PROBE_FLAG, longOptions[optionIndex].name) == 0) {
                        probeForUpdates = YES;
                    } else if (strcmp(INTERACTIVE_FLAG, longOptions[optionIndex].name) == 0) {
                        interactive = YES;
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
        
        if (probeForUpdates && (applicationPath != nil || deferInstall || checkForUpdatesNow || interactive)) {
            fprintf(stderr, "Error: --%s does not work together with --%s, --%s, --%s, --%s\n", PROBE_FLAG, APPLICATION_FLAG, DEFER_FLAG, CHECK_NOW_FLAG, INTERACTIVE_FLAG);
            return EXIT_FAILURE;
        }
        
        SUUpdatePermissionResponse *updatePermissionResponse = nil;
        if (grantAutomaticChecking) {
            updatePermissionResponse = [[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:YES sendSystemProfile:sendProfile];
        }
        
        SPUCommandLineDriver *driver = [[SPUCommandLineDriver alloc] initWithUpdateBundlePath:updatePath applicationBundlePath:applicationPath customFeedURL:feedURL updatePermissionResponse:updatePermissionResponse deferInstallation:deferInstall interactiveInstallation:interactive verbose:verbose];
        if (driver == nil) {
            fprintf(stderr, "Error: Failed to initialize updater. Are the bundle paths provided valid?\n");
            return EXIT_FAILURE;
        }
        
        if (probeForUpdates) {
            [driver probeForUpdates];
        } else {
            [driver runAndCheckForUpdatesNow:checkForUpdatesNow];
        }
        [[NSRunLoop currentRunLoop] run];
    }
    
    return EXIT_SUCCESS;
}
