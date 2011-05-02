//
//  SUSystemProfiler.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/22/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//  Adapted from Sparkle+, by Tom Harrington.
//

#import "SUSystemProfiler.h"

#import "SUHost.h"
#import <sys/sysctl.h>

@implementation SUSystemProfiler
+ (SUSystemProfiler *)sharedSystemProfiler
{
	static SUSystemProfiler *sharedSystemProfiler = nil;
	if (!sharedSystemProfiler)
		sharedSystemProfiler = [[self alloc] init];
	return sharedSystemProfiler;
}

- (NSDictionary *)modelTranslationTable
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SUModelTranslation" ofType:@"plist"];
	return [[[NSDictionary alloc] initWithContentsOfFile:path] autorelease];
}

- (NSMutableArray *)systemProfileArrayForHost:(SUHost *)host
{
	NSDictionary *modelTranslation = [self modelTranslationTable];
	
	// Gather profile information and append it to the URL.
	NSMutableArray *profileArray = [NSMutableArray array];
	NSArray *profileDictKeys = [NSArray arrayWithObjects:@"key", @"displayKey", @"value", @"displayValue", nil];
	int error = 0;
	int value = 0;
	size_t length = sizeof(value);
	
	// OS version
	NSString *currentSystemVersion = [SUHost systemVersionString];
	if (currentSystemVersion != nil)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"osVersion",@"OS Version",currentSystemVersion,currentSystemVersion,nil] forKeys:profileDictKeys]];
	
	// CPU type (decoder info for values found here is in mach/machine.h)
	error = sysctlbyname("hw.cputype", &value, &length, NULL, 0);
	int cpuType = -1;
	if (error == 0) {
		cpuType = value;
		NSString *visibleCPUType;
		switch(value) {
			case CPU_TYPE_X86:		visibleCPUType = @"Intel";		break;
			case CPU_TYPE_POWERPC:	visibleCPUType = @"PowerPC";	break;
			default:				visibleCPUType = @"Unknown";	break;
		}
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cputype",@"CPU Type", [NSNumber numberWithInt:value], visibleCPUType,nil] forKeys:profileDictKeys]];
	}
	error = sysctlbyname("hw.cpu64bit_capable", &value, &length, NULL, 0);
	if(error != 0)
		error = sysctlbyname("hw.optional.x86_64", &value, &length, NULL, 0); //x86 specific
	if(error != 0)
		error = sysctlbyname("hw.optional.64bitops", &value, &length, NULL, 0); //PPC specific
	
	BOOL is64bit = NO;
	
	if (error == 0) {
		is64bit = value == 1;
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cpu64bit", @"CPU is 64-Bit?", [NSNumber numberWithBool:is64bit], is64bit ? @"Yes" : @"No", nil] forKeys:profileDictKeys]];
	}
	error = sysctlbyname("hw.cpusubtype", &value, &length, NULL, 0);
	if (error == 0) {
		NSString *visibleCPUSubType;
		if (cpuType == 7) {
			// Intel
			visibleCPUSubType = is64bit ? @"Intel Core 2" : @"Intel Core";	// If anyone knows how to tell a Core Duo from a Core Solo, please email tph@atomicbird.com
		} else if (cpuType == 18) {
			// PowerPC
			switch(value) {
				case 9:					visibleCPUSubType=@"G3";	break;
				case 10:	case 11:	visibleCPUSubType=@"G4";	break;
				case 100:				visibleCPUSubType=@"G5";	break;
				default:				visibleCPUSubType=@"Other";	break;
			}
		} else {
			visibleCPUSubType = @"Other";
		}
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cpusubtype",@"CPU Subtype", [NSNumber numberWithInt:value], visibleCPUSubType,nil] forKeys:profileDictKeys]];
	}
	error = sysctlbyname("hw.model", NULL, &length, NULL, 0);
	if (error == 0) {
		char *cpuModel = (char *)malloc(sizeof(char) * length);
		if (cpuModel != NULL) {
			error = sysctlbyname("hw.model", cpuModel, &length, NULL, 0);
			if (error == 0) {
				NSString *rawModelName = [NSString stringWithUTF8String:cpuModel];
				NSString *visibleModelName = [modelTranslation objectForKey:rawModelName];
				if (visibleModelName == nil)
					visibleModelName = rawModelName;
				[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"model",@"Mac Model", rawModelName, visibleModelName, nil] forKeys:profileDictKeys]];
			}
			free(cpuModel);
		}
	}
	
	// Number of CPUs
	error = sysctlbyname("hw.ncpu", &value, &length, NULL, 0);
	if (error == 0)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"ncpu",@"Number of CPUs", [NSNumber numberWithInt:value], [NSNumber numberWithInt:value],nil] forKeys:profileDictKeys]];
	
	// User preferred language
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSArray *languages = [defs objectForKey:@"AppleLanguages"];
	if ([languages count] > 0)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"lang",@"Preferred Language", [languages objectAtIndex:0], [languages objectAtIndex:0],nil] forKeys:profileDictKeys]];
	
	// Application sending the request
	NSString *appName = [host name];
	if (appName)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"appName",@"Application Name", appName, appName,nil] forKeys:profileDictKeys]];
	NSString *appVersion = [host version];
	if (appVersion)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"appVersion",@"Application Version", appVersion, appVersion,nil] forKeys:profileDictKeys]];
	
	// Number of displays?
	// CPU speed
	SInt32 gestaltInfo;
	OSErr err = Gestalt(gestaltProcClkSpeedMHz,&gestaltInfo);
	if (err == noErr)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cpuFreqMHz",@"CPU Speed (GHz)", [NSNumber numberWithInt:gestaltInfo], [NSNumber numberWithDouble:gestaltInfo/1000.0],nil] forKeys:profileDictKeys]];
	
	// amount of RAM
	err = Gestalt(gestaltPhysicalRAMSizeInMegabytes,&gestaltInfo);
	if (err == noErr)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"ramMB",@"Memory (MB)", [NSNumber numberWithInt:gestaltInfo], [NSNumber numberWithInt:gestaltInfo],nil] forKeys:profileDictKeys]];
	
	return profileArray;
}

@end
