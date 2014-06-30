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

@interface SUHost ()
@property (retain, readwrite) NSBundle *bundle;
@end

@implementation SUHost
@synthesize bundle;

- (instancetype)initWithBundle:(NSBundle *)aBundle
{
	if ((self = [super init]))
	{
		if (aBundle == nil) aBundle = [NSBundle mainBundle];
        self.bundle = aBundle;
		if (![bundle bundleIdentifier]) {
			SULog(@"Sparkle Error: the bundle being updated at %@ has no CFBundleIdentifier! This will cause preference read/write to not work properly.", bundle);
		}

		defaultsDomain = [[bundle objectForInfoDictionaryKey:SUDefaultsDomainKey] retain];
		if (!defaultsDomain) {
			defaultsDomain = [[bundle bundleIdentifier] retain];
		}

		// If we're using the main bundle's defaults we'll use the standard user defaults mechanism, otherwise we have to get CF-y.
		usesStandardUserDefaults = [defaultsDomain isEqualToString:[[NSBundle mainBundle] bundleIdentifier]];
    }
    return self;
}

- (void)dealloc
{
	[defaultsDomain release];
	self.bundle = nil;
	[super dealloc];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [self bundlePath], [self installationPath]]; }

- (NSString *)bundlePath
{
    return [bundle bundlePath];
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
    NSString *normalizedAppPath = [[[bundle bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent: [NSString stringWithFormat: @"%@.%@", [bundle objectForInfoDictionaryKey:@"CFBundleName"], [[bundle bundlePath] pathExtension]]];
	if (![[NSFileManager defaultManager] fileExistsAtPath:[[[bundle bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent: [NSString stringWithFormat: @"%@.%@", [bundle objectForInfoDictionaryKey:@"CFBundleName"], [[bundle bundlePath] pathExtension]]]]) {
        return normalizedAppPath;
	}
#endif
	return [bundle bundlePath];
}

- (NSString *)name
{
	NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (name) return name;

	name = [self objectForInfoDictionaryKey:@"CFBundleName"];
	if (name) return name;

	return [[[NSFileManager defaultManager] displayNameAtPath:[bundle bundlePath]] stringByDeletingPathExtension];
}

- (NSString *)version
{
	NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
	if (!version || [version isEqualToString:@""])
		[NSException raise:@"SUNoVersionException" format:@"This host (%@) has no CFBundleVersion! This attribute is required.", [self bundlePath]];
	return version;
}

- (NSString *)displayVersion
{
	NSString *shortVersionString = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	if (shortVersionString)
		return shortVersionString;
	else
		return [self version]; // Fall back on the normal version string.
}

- (NSImage *)icon
{
	// Cache the application icon.
	NSString *iconPath = [bundle pathForResource:[bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:@"icns"];
	// According to the OS X docs, "CFBundleIconFile - This key identifies the file containing
	// the icon for the bundle. The filename you specify does not need to include the .icns
	// extension, although it may."
	//
	// However, if it *does* include the '.icns' the above method fails (tested on OS X 10.3.9) so we'll also try:
	if (!iconPath) {
		iconPath = [bundle pathForResource:[bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType: nil];
	}
	NSImage *icon = [[[NSImage alloc] initWithContentsOfFile:iconPath] autorelease];
	// Use a default icon if none is defined.
	if (!icon) {
		BOOL isMainBundle = (bundle == [NSBundle mainBundle]);

		NSString *fileType = isMainBundle ? (NSString*)kUTTypeApplication : (NSString*)kUTTypeBundle;
		icon = [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
	}
	return icon;
}

- (BOOL)isRunningOnReadOnlyVolume
{
	struct statfs statfs_info;
	statfs([[bundle bundlePath] fileSystemRepresentation], &statfs_info);
	return (statfs_info.f_flags & MNT_RDONLY);
}

- (BOOL)isBackgroundApplication
{
	return ([[NSApplication sharedApplication] activationPolicy] == NSApplicationActivationPolicyAccessory);
}

- (NSString *)publicDSAKey
{
	// Maybe the key is just a string in the Info.plist.
	NSString *key = [bundle objectForInfoDictionaryKey:SUPublicDSAKeyKey];
	if (key) { return key; }

	// More likely, we've got a reference to a Resources file by filename:
	NSString *keyFilename = [self objectForInfoDictionaryKey:SUPublicDSAKeyFileKey];
	if (!keyFilename) { return nil; }
	NSError *ignoreErr = nil;
	return [NSString stringWithContentsOfFile:[bundle pathForResource:keyFilename ofType:nil] encoding:NSASCIIStringEncoding error: &ignoreErr];
}

- (NSArray *)systemProfile
{
	return [[SUSystemProfiler sharedSystemProfiler] systemProfileArrayForHost:self];
}

- (id)objectForInfoDictionaryKey:(NSString *)key
{
    return [bundle objectForInfoDictionaryKey:key];
}

- (BOOL)boolForInfoDictionaryKey:(NSString *)key
{
	return [[self objectForInfoDictionaryKey:key] boolValue];
}

- (id)objectForUserDefaultsKey:(NSString *)defaultName
{
    if (!defaultName || !defaultsDomain) {
        return nil;
    }

	// Under Tiger, CFPreferencesCopyAppValue doesn't get values from NSRegistrationDomain, so anything
	// passed into -[NSUserDefaults registerDefaults:] is ignored.  The following line falls
	// back to using NSUserDefaults, but only if the host bundle is the main bundle.
	if (usesStandardUserDefaults) {
		return [[NSUserDefaults standardUserDefaults] objectForKey:defaultName];
	}

	CFPropertyListRef obj = CFPreferencesCopyAppValue((CFStringRef)defaultName, (CFStringRef)defaultsDomain);
	return CFBridgingRelease(obj);
}

- (void)setObject:(id)value forUserDefaultsKey:(NSString *)defaultName
{
	if (usesStandardUserDefaults)
	{
		[[NSUserDefaults standardUserDefaults] setObject:value forKey:defaultName];
	}
	else
	{
		CFPreferencesSetValue((CFStringRef)defaultName, value, (CFStringRef)defaultsDomain,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
		CFPreferencesSynchronize((CFStringRef)defaultsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	}
}

- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName
{
	if (usesStandardUserDefaults) {
		return [[NSUserDefaults standardUserDefaults] boolForKey:defaultName];
	}

	BOOL value;
	CFPropertyListRef plr = CFPreferencesCopyAppValue((CFStringRef)defaultName, (CFStringRef)defaultsDomain);
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
	if (usesStandardUserDefaults)
	{
		[[NSUserDefaults standardUserDefaults] setBool:value forKey:defaultName];
	}
	else
	{
		CFPreferencesSetValue((CFStringRef)defaultName, (CFBooleanRef)@(value), (CFStringRef)defaultsDomain,  kCFPreferencesCurrentUser,  kCFPreferencesAnyHost);
		CFPreferencesSynchronize((CFStringRef)defaultsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
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
	NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
	return [NSDictionary dictionaryWithContentsOfFile:versionPlistPath][@"ProductVersion"];
}

@end
