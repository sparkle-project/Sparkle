#import <Foundation/Foundation.h>
#import "AppInstaller.h"

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
        if (args.count != 3) {
            return EXIT_FAILURE;
        }
        
        NSString *hostBundleIdentifier = args[1];
        BOOL inheritsPrivileges = args[2].boolValue;
        
        AppInstaller *appInstaller = [[AppInstaller alloc] initWithHostBundleIdentifier:hostBundleIdentifier inheritsPrivileges:inheritsPrivileges];
        [appInstaller start];
        [[NSRunLoop currentRunLoop] run];
    }

    return EXIT_SUCCESS;
}
