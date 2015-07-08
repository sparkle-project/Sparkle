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
//  updater object class inside XIB file from SUUpdater to DM_SUUpdater updating process won't be broken.

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
        if (Nil != SUUpdaterClass)
        {
            objc_registerClassPair(SUUpdaterClass);
        }
        Class SUUpdaterMetaclass = objc_getMetaClass(class_getName(SUUpdaterClass));
        
        Class LoaderClass = [self class];
        Class LoaderMetaclass = objc_getMetaClass(class_getName(LoaderClass));
        
        BOOL success = SUUpdaterClass != Nil && SUUpdaterMetaclass != Nil;
        void *runtimeMethods[][3] = {
            { (__bridge void *)SUUpdaterClass, (__bridge void *)LoaderClass, @selector(init) },
            { (__bridge void *)SUUpdaterClass, (__bridge void *)LoaderClass, @selector(initForBundle:) },
            { (__bridge void *)SUUpdaterMetaclass, (__bridge void *)LoaderMetaclass, @selector(sharedUpdater) },
            { (__bridge void *)SUUpdaterMetaclass, (__bridge void *)LoaderMetaclass, @selector(updaterForBundle:) },
        };
        size_t methodsCount = sizeof(runtimeMethods) / sizeof(runtimeMethods[0]);
        for (size_t i = 0; success && i < methodsCount; ++i)
        {
            Class changeClass = (__bridge Class)runtimeMethods[i][0];
            Class prototypeClass = (__bridge Class)runtimeMethods[i][1];
            SEL selector = runtimeMethods[i][2];
            
            IMP implementation = class_getMethodImplementation(prototypeClass, selector);
            const char *types = method_getTypeEncoding(class_getInstanceMethod(prototypeClass, selector));

            success = class_addMethod(changeClass, selector, implementation, types);
        }
        
        if (!success)
        {
            objc_disposeClassPair(SUUpdaterClass);
        }
    }
}

#pragma mark - Public creation methods

- (id)init
{
    return (id)[[SUUpdaterWorking alloc] init];
}

- (id)initForBundle:(NSBundle *)bundle
{
    return (id)[[SUUpdaterWorking alloc] initForBundle:bundle];
}

+ (SUUpdater *)sharedUpdater
{
    return [SUUpdaterWorking sharedUpdater];
}

+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle
{
    return [SUUpdaterWorking updaterForBundle:bundle];
}

@end
