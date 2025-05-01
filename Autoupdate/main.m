#import <Foundation/Foundation.h>
#import "AppInstaller.h"


#include "AppKitPrevention.h"

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
        if (args.count != 4) {
            return EXIT_FAILURE;
        }
        
        NSString *hostBundleIdentifier = args[1];
        NSString *homeDirectory = args[2];
        NSString *userName = args[3];
        
        AppInstaller *appInstaller = [[AppInstaller alloc] initWithHostBundleIdentifier:hostBundleIdentifier homeDirectory:homeDirectory userName:userName];
        [appInstaller start];
        
        // Ignore SIGTERM because we are going to catch it ourselves
        signal(SIGTERM, SIG_IGN);
        // Ignore SIGPIPE because we won't want read or write failures due to broken pipe to unexpectably
        // terminate the process (e.g, when extracting archives or performing package installs).
        signal(SIGPIPE, SIG_IGN);
        
        dispatch_source_t sigtermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigtermSource, ^{
            // Don't clear the update directory because the installer may be in middle of installing an update
            // We still need to set an event handler for receiving SIGTERM though, otherwise our job may not terminate
            // (This is also recommended from the developer documentation).
            // Simply exit with SIGTERM if we receive this signal
            exit(SIGTERM);
        });
        dispatch_resume(sigtermSource);
        
        [[NSRunLoop currentRunLoop] run];
    }

    return EXIT_SUCCESS;
}
