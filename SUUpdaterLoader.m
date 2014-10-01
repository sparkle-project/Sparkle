//
//  SUUpdaterProxy.m
//  Sparkle
//
//  Created by Dmytro Tretiakov on 10/1/14.
//
//

#import "SUUpdater.h"
#import <objc/runtime.h>

// This is a proxy for DM_SUUpdater class used in DevMateSparkle_lib target.
//  In cases when developer uses this lib in it's own project but forgot to change
//  updater object class inside XIB file from SUUpdater to DM_SUUpdater updating process will be broken
//  with additional console log about absence of SUUpdater class. This class implementation will
//  log additional helpful info to console

static NSString *sOriginalSUUpdaterClass = @"SUUpdater";

@interface SUUpdaterLoader : NSObject
@end

@implementation SUUpdaterLoader

+ (void)load
{
    if (Nil == NSClassFromString(sOriginalSUUpdaterClass))
    {
        // Custom Sparkle.framework is absent
        // Add own SUUpdater proxy class
        Class SUUpdaterClass = objc_allocateClassPair([NSObject class], [sOriginalSUUpdaterClass UTF8String], 0);
        
        BOOL success = SUUpdaterClass != Nil;
        if (success)
        {
            SEL selector = @selector(init);
            IMP implementation = [self instanceMethodForSelector:selector];
            const char *types = method_getTypeEncoding(class_getInstanceMethod(self, selector));

            success = class_addMethod(SUUpdaterClass, selector, implementation, types);
        }
        
        if (success)
        {
            objc_registerClassPair(SUUpdaterClass);
        }
    }
}

- (id)init
{
    NSLog(@"===========================================");
    NSLog(@"WARNING! Use new %@ class instead of %@ everywhere in your project (including XIB files)!", NSStringFromClass([SUUpdater class]), sOriginalSUUpdaterClass);
    NSLog(@"===========================================");

    [self release];
    return (id)[SUUpdaterWorking sharedUpdater];
}

@end
