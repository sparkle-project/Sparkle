
#import <Cocoa/Cocoa.h>

#import <unistd.h>

@interface TerminationListener : NSObject
{
@private
	NSString *executablePath;
    NSMutableArray *executableArguments;
	pid_t parentProcessId;
}

- (void)relaunch __dead2;

@end

@implementation TerminationListener

- (void)watchdog:(NSTimer *)timer
{
	ProcessSerialNumber psn;
	if (GetProcessForPID(parentProcessId, &psn) == procNotFound)
		[self relaunch];
}

- (id) init
{
	self = [super init];
	if (self != nil)
	{
        executableArguments = [[[NSMutableArray alloc] initWithArray:[[NSProcessInfo processInfo] arguments]] autorelease];
        // Remove the first three arguments
        if ([executableArguments count] >= 3) {
            // Remove relaunch path
            [executableArguments removeObjectAtIndex:0];
            // Set and remove executablePath
            executablePath = [executableArguments objectAtIndex:0];
            [executableArguments removeObjectAtIndex:0];
            // Set and remove parentProcessId
            parentProcessId = (pid_t)[[executableArguments objectAtIndex:0] intValue];
            [executableArguments removeObjectAtIndex:0];
        }
		if (getppid() == 1) // ppid is launchd (1) => parent terminated already
			[self relaunch];
		[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(watchdog:) userInfo:nil repeats:YES];
	}
	return self;
}

- (void) relaunch
{   
    // Relaunch binary application
    if ([[executablePath pathExtension] isEqualToString:@""]) {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/usr/bin/arch"];
        [executableArguments insertObject:executablePath atIndex:0];
#if defined __ppc__ || defined __i368__
        [executableArguments insertObject:@"-32" atIndex:0];
#elif defined __ppc64__ || defined __x86_64__
        [executableArguments insertObject:@"-64" atIndex:0];
#endif
        [task setArguments:executableArguments];
        [task launch];
        [task release];
    }
    // Relaunch GUI application
    else {
        [[NSWorkspace sharedWorkspace] openFile:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:[executablePath UTF8String] length:strlen([executablePath UTF8String])]];
    }

	NSString* path = NSTemporaryDirectory();
	if (path)
	{
		path = [path stringByAppendingPathComponent:@"relaunch"];
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
		[[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
#else
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
#endif
	}
	exit(0);
}

@end

int main (int argc, const char * argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    [NSApplication sharedApplication];
	[[[TerminationListener alloc] init] autorelease];
	[[NSApplication sharedApplication] run];

	[pool drain];
	return EXIT_SUCCESS;
}
