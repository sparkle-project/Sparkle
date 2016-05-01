//
//  main.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUCommandLineDriver.h"
#include <getopt.h>

#define APPLICATION_FLAG "application"
#define DEFER_FLAG "defer"
#define VERBOSE_FLAG "verbose"

static void printUsage(char **argv)
{
    fprintf(stderr, "Usage: %s <update-bundle-path> [--%s <path-to-application>] [--%s] [--%s]\n", argv[0], APPLICATION_FLAG, DEFER_FLAG, VERBOSE_FLAG);
}

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        struct option longOptions[] = {
            {APPLICATION_FLAG, required_argument, NULL, 0},
            {DEFER_FLAG, no_argument, NULL, 0},
            {VERBOSE_FLAG, no_argument, NULL, 0},
            {0, 0, 0, 0}
        };
        
        NSString *applicationPath = nil;
        BOOL deferInstall = NO;
        BOOL verbose = NO;
        
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
        
        SUCommandLineDriver *driver = [[SUCommandLineDriver alloc] initWithUpdateBundlePath:updatePath applicationBundlePath:applicationPath deferInstallation:deferInstall verbose:verbose];
        if (driver == nil) {
            printUsage(argv);
            return EXIT_FAILURE;
        }
        
        [driver run];
        [[NSRunLoop currentRunLoop] run];
    }
    
    return EXIT_SUCCESS;
}
