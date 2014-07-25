//
//  SUHost.m
//  Sparkle
//
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUHost.h"

#import "SUConstants.h"
#import "SUSystemProfiler.h"
#include <sys/mount.h> // For statfs for isRunningOnReadOnlyVolume
#import "SULog.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101000
typedef struct {
    NSInteger majorVersion;
    NSInteger minorVersion;
    NSInteger patchVersion;
} NSOperatingSystemVersion;
@interface NSProcessInfo ()
- (NSOperatingSystemVersion)operatingSystemVersion;
@end
#endif

@interface SUHost ()

@property (strong, readwrite) NSBundle *bundle;
@property (copy) NSString *defaultsDomain;
@property (assign) BOOL usesStandardUserDefaults;

@end

@implementation SUHost

@synthesize bundle;
@synthesize defaultsDomain;
@synthesize usesStandardUserDefaults;

- (instancetype)initWithBundle:(NSBundle *)aBundle
{
	if ((self = [super init]))
	{
		if (aBundle == nil) aBundle = [NSBundle mainBundle];
        self.bundle = aBundle;
        if (![self.bundle bundleIdentifier]) {
            SULog(@"Sparkle Error: the bundle being updated at %@ has no CFBundleIdentifier! This will cause preference read/write to not work properly.", self.bundle);
        }

        self.defaultsDomain = [self.bundle objectForInfoDictionaryKey:SUDefaultsDomainKey];
        if (!self.defaultsDomain) {
            self.defaultsDomain = [self.bundle bundleIdentifier];
        }

        // If we're using the main bundle's defaults we'll use the standard user defaults mechanism, otherwise we have to get CF-y.
        usesStandardUserDefaults = !self.defaultsDomain || [self.defaultsDomain isEqualToString:[[NSBundle mainBundle] bundleIdentifier]];
    }
    return self;
}


- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [self bundlePath], [self installationPath]]; }

- (NSString *)bundlePath
{
    return [self.bundle bundlePath];
}

- (NSString *)appSupportPath
{
    NSArray *appSupportPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupportPath = nil;
    if (!appSupportPaths || [appSupportPaths count] == 0)
    {
        SULog(@"Failed to find app support directory! Using ~/Library/Application Support...");
        appSupportPath = [@"~/Library/Application Support" stringByExpandingTildeInPath];
    }
	else {
        appSupportPath = appSupportPaths[0];
    }
    appSupportPath = [appSupportPath stringByAppendingPathComponent:[self name]];
    appSupportPath = [appSupportPath stringByAppendingPathComponent:@".Sparkle"];
    return appSupportPath;
}

- (NSString *)installationPath
{
#if NORMALIZE_INSTALLED_APP_NAME
    // We'll install to "#{CFBundleName}.app", but only if that path doesn't already exist. If we're "Foo 4.2.app," and there's a "Foo.app" in this directory, we don't want to overwrite it! But if there's no "Foo.app," we'll take that name.
    NSString *normalizedAppPath = [[[self.bundle bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [self.bundle objectForInfoDictionaryKey:@"CFBundleName"], [[self.bundle bundlePath] pathExtension]]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[[[self.bundle bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [self.bundle objectForInfoDictionaryKey:@"CFBundleName"], [[self.bundle bundlePath] pathExtension]]]]) {
        return normalizedAppPath;
    }
#endif
    return [self.bundle bundlePath];
}

- (NSString *)name
{
    NSString *name = [self.bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (name) return name;

    name = [self objectForInfoDictionaryKey:@"CFBundleName"];
	if (name) return name;

    return [[[NSFileManager defaultManager] displayNameAtPath:[self.bundle bundlePath]] stringByDeletingPathExtension];
}

- (NSString *)version
{
    NSString *version = [self.bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (!version || [version isEqualToString:@""])
        [NSException raise:@"SUNoVersionException" format:@"This host (%@) has no CFBundleVersion! This attribute is required.", [self bundlePath]];
    return version;
}

- (NSString *)displayVersion
{
    NSString *shortVersionString = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (shortVersionString)
        return shortVersionString;
    else
        return [self version]; // Fall back on the normal version string.
}

- (NSImage *)icon
{
    // Cache the application icon.
    NSString *iconPath = [self.bundle pathForResource:[self.bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:@"icns"];
    // According to the OS X docs, "CFBundleIconFile - This key identifies the file containing
    // the icon for the bundle. The filename you specify does not need to include the .icns
    // extension, although it may."
    //
    // However, if it *does* include the '.icns' the above method fails (tested on OS X 10.3.9) so we'll also try:
    if (!iconPath) {
        iconPath = [self.bundle pathForResource:[self.bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:nil];
    }
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    // Use a default icon if none is defined.
    if (!icon) {
        BOOL isMainBundle = (self.bundle == [NSBundle mainBundle]);

        NSString *fileType = isMainBundle ? (NSString *)kUTTypeApplication : (NSString *)kUTTypeBundle;
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
    }
    return icon;
}

- (BOOL)isRunningOnReadOnlyVolume
{
    struct statfs statfs_info;
    statfs([[self.bundle bundlePath] fileSystemRepresentation], &statfs_info);
    return (statfs_info.f_flags & MNT_RDONLY);
}

- (BOOL)isBackgroundApplication
{
    return ([[NSApplication sharedApplication] activationPolicy] == NSApplicationActivationPolicyAccessory);
}

- (NSString *)publicDSAKey
{
    // Maybe the key is just a string in the Info.plist.
    NSString *key = [self.bundle objectForInfoDictionaryKey:SUPublicDSAKeyKey];
	if (key) { return key; }

    // More likely, we've got a reference to a Resources file by filename:
    NSString *keyFilename = [self objectForInfoDictionaryKey:SUPublicDSAKeyFileKey];
	if (!keyFilename) { return nil; }
    NSError *ignoreErr = nil;
    return [NSString stringWithContentsOfFile:[self.bundle pathForResource:keyFilename ofType:nil] encoding:NSASCIIStringEncoding error:&ignoreErr];
}

- (NSArray *)systemProfile
{
    return [[SUSystemProfiler sharedSystemProfiler] systemProfileArrayForHost:self];
}

- (id)objectForInfoDictionaryKey:(NSString *)key
{
    return [self.bundle objectForInfoDictionaryKey:key];
}

- (BOOL)boolForInfoDictionaryKey:(NSString *)key
{
    return [[self objectForInfoDictionaryKey:key] boolValue];
}

- (id)objectForUserDefaultsKey:(NSString *)defaultName
{
    if (!defaultName || !self.defaultsDomain) {
        return nil;
    }

    // Under Tiger, CFPreferencesCopyAppValue doesn't get values from NSRegistrationDomain, so anything
    // passed into -[NSUserDefaults registerDefaults:] is ignored.  The following line falls
    // back to using NSUserDefaults, but only if the host bundle is the main bundle.
    if (self.usesStandardUserDefaults) {
        return [[NSUserDefaults standardUserDefaults] objectForKey:defaultName];
    }

    CFPropertyListRef obj = CFPreferencesCopyAppValue((__bridge CFStringRef)defaultName, (__bridge CFStringRef)self.defaultsDomain);
    return CFBridgingRelease(obj);
}

- (void)setObject:(id)value forUserDefaultsKey:(NSString *)defaultName
{
	if (self.usesStandardUserDefaults)
	{
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:defaultName];
	}
	else
	{
        CFPreferencesSetValue((__bridge CFStringRef)defaultName, (__bridge CFPropertyListRef)(value), (__bridge CFStringRef)self.defaultsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize((__bridge CFStringRef)self.defaultsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
}

- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName
{
    if (self.usesStandardUserDefaults) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:defaultName];
    }

    BOOL value;
    CFPropertyListRef plr = CFPreferencesCopyAppValue((__bridge CFStringRef)defaultName, (__bridge CFStringRef)self.defaultsDomain);
    if (plr == NULL) {
        value = NO;
	}
	else
	{
        value = (BOOL)CFBooleanGetValue((CFBooleanRef)plr);
        CFRelease(plr);
    }
    return value;
}

- (void)setBool:(BOOL)value forUserDefaultsKey:(NSString *)defaultName
{
	if (self.usesStandardUserDefaults)
	{
        [[NSUserDefaults standardUserDefaults] setBool:value forKey:defaultName];
	}
	else
	{
        CFPreferencesSetValue((__bridge CFStringRef)defaultName, (__bridge CFBooleanRef) @(value), (__bridge CFStringRef)self.defaultsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize((__bridge CFStringRef)self.defaultsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
}

- (id)objectForKey:(NSString *)key {
    return [self objectForUserDefaultsKey:key] ? [self objectForUserDefaultsKey:key] : [self objectForInfoDictionaryKey:key];
}

- (BOOL)boolForKey:(NSString *)key {
    return [self objectForUserDefaultsKey:key] ? [self boolForUserDefaultsKey:key] : [self boolForInfoDictionaryKey:key];
}

+ (NSString *)systemVersionString
{
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090 // Present in 10.9 despite NS_AVAILABLE's claims
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wselector"
    // Xcode 5.1.1: operatingSystemVersion is clearly declared, must warn due to a compiler bug?
    if (![NSProcessInfo instancesRespondToSelector:@selector(operatingSystemVersion)])
#pragma clang diagnostic pop
    {
        NSURL *coreServices = [[NSFileManager defaultManager] URLForDirectory:NSCoreServiceDirectory inDomain:NSSystemDomainMask appropriateForURL:nil create:NO error:nil];
        return [NSDictionary dictionaryWithContentsOfURL:[coreServices URLByAppendingPathComponent:@"SystemVersion.plist"]][@"ProductVersion"];
    }
#endif
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion];
}

@end
