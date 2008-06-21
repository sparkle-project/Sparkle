//
//  NSWorkspace_RBAdditions.m
//  PathProps
//
//  Created by Rainer Brockerhoff on 10/04/2007.
//  Copyright 2007 Rainer Brockerhoff. All rights reserved.
//

#import "Sparkle.h"
#import "NSWorkspace_RBAdditions.h"

#include <IOKit/IOKitLib.h>
#include <sys/mount.h>
#include <mach/mach.h>

NSString* NSWorkspace_RBfstypename = @"NSWorkspace_RBfstypename";
NSString* NSWorkspace_RBmntonname = @"NSWorkspace_RBmntonname";
NSString* NSWorkspace_RBmntfromname = @"NSWorkspace_RBmntfromname";
NSString* NSWorkspace_RBdeviceinfo = @"NSWorkspace_RBdeviceinfo";
NSString* NSWorkspace_RBimagefilepath = @"NSWorkspace_RBimagefilepath";
NSString* NSWorkspace_RBconnectiontype = @"NSWorkspace_RBconnectiontype";
NSString* NSWorkspace_RBpartitionscheme = @"NSWorkspace_RBpartitionscheme";
NSString* NSWorkspace_RBserverURL = @"NSWorkspace_RBserverURL";

// This static funtion concatenates two strings, but first checks several possibilities...
// like one or the other nil, or one containing the other already.

static NSString* AddPart(NSString* first,NSString* second) {
	if (!second) {
		return first;
	}
	second = [second stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (first) {
		if ([first rangeOfString:second options:NSCaseInsensitiveSearch].location==NSNotFound) {
			if ([second rangeOfString:first options:NSCaseInsensitiveSearch].location==NSNotFound) {
				return [NSString stringWithFormat:@"%@; %@",first,second];
			}
			return second;
		}
		return first;
	}
	return second;
}

// This static functions recurses "upwards" over the IO registry. Returns strings that are concatenated
// and ultimately end up under the NSWorkspace_RBdeviceinfo key.
// This isn't too robust in that it assumes that objects returned by the objectForKey methods are
// either strings or dictionaries. A "standard" implementations would use either only CoreFoundation and
// IOKit calls for this, or do more robust type checking on the returned objects.
//
// Also notice that this works as determined experimentally in 10.4.9, there's no official docs I could find.
// YMMV, and it may stop working in any new version of Mac OS X.

static NSString* CheckParents(io_object_t thing,NSString* part,NSMutableDictionary* dict) {
	NSString* result = part;
    io_iterator_t parentsIterator = 0;
    kern_return_t kernResult = IORegistryEntryGetParentIterator(thing,kIOServicePlane,&parentsIterator);
    if ((kernResult==KERN_SUCCESS)&&parentsIterator) {
		io_object_t nextParent = 0;
		while ((nextParent = IOIteratorNext(parentsIterator))) {
			NSDictionary* props = nil;
			NSString* image = nil;
			NSString* partition = nil;
			NSString* connection = nil;
			kernResult = IORegistryEntryCreateCFProperties(nextParent,(CFMutableDictionaryRef*)&props,kCFAllocatorDefault,0);
			if (IOObjectConformsTo(nextParent,"IOApplePartitionScheme")) {
				partition = [props objectForKey:@"Content Mask"];
			} else if (IOObjectConformsTo(nextParent,"IOMedia")) {
				partition = [props objectForKey:@"Content"];
			} else if (IOObjectConformsTo(nextParent,"IODiskImageBlockStorageDeviceOutKernel")) {
				NSData* data = nil;
				if ((data = [[props objectForKey:@"Protocol Characteristics"] objectForKey:@"Virtual Interface Location Path"])) {
					image = [[[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding] autorelease];
				}
			} else if (IOObjectConformsTo(nextParent,"IOHDIXHDDriveInKernel")) {
				image = [props objectForKey:@"KDIURLPath"];
			}
			NSDictionary* subdict;
			if ((subdict = [props objectForKey:@"Protocol Characteristics"])) {
				connection = [subdict objectForKey:@"Physical Interconnect"];
			} else {
				connection = [props objectForKey:@"Physical Interconnect"];
			}
			if (connection) {
				[dict setObject:AddPart([dict objectForKey:NSWorkspace_RBconnectiontype],connection) forKey:NSWorkspace_RBconnectiontype];
			}
			if (partition) {
				[dict setObject:partition forKey:NSWorkspace_RBpartitionscheme];
			}
			if (image) {
				[dict setObject:image forKey:NSWorkspace_RBimagefilepath];
			}
			NSString* value;
			if ((subdict = [props objectForKey:@"Device Characteristics"])) {
				if ((value = [subdict objectForKey:@"Product Name"])) {
					result = AddPart(result,value);
				}
				if ((value = [subdict objectForKey:@"Product Revision Level"])) {
					result = AddPart(result,value);
				}
				if ((value = [subdict objectForKey:@"Vendor Name"])) {
					result = AddPart(result,value);
				}
			}
			if ((value = [props objectForKey:@"USB Serial Number"])) {
				result = AddPart(result,value);
			}
			if ((value = [props objectForKey:@"USB Vendor Name"])) {
				result = AddPart(result,value);
			}
			io_name_t ts;  // char[128]
			NSString* cls = ( IOObjectGetClass (nextParent, ts) == KERN_SUCCESS ) ? [NSString stringWithUTF8String:ts ] : nil;
			if (![cls isEqualToString:@"IOPCIDevice"]) {
			
// Uncomment the following line to have the device tree dumped to the console.
//				NSLog(@"=================================> %@:%@\n",cls,props);

				result = CheckParents(nextParent,result,dict);
			}
			if (props) { CFRelease(props); }
			IOObjectRelease(nextParent);
		}
    }
    if (parentsIterator) {
		IOObjectRelease(parentsIterator);
    }
	return result;
}

@implementation NSWorkspace (NSWorkspace_RBAdditions)

// Returns a NSDictionary with properties for the path. See details in the .h file.
// This assumes that the length of path is less than PATH_MAX (currently 1024 characters).

- (NSDictionary*)propertiesForPath:(NSString*)path {
	const char* ccpath = [path fileSystemRepresentation];
	NSMutableDictionary* result = nil;
	struct statfs fs = {};
	if (!statfs(ccpath,&fs)) {
		NSString* from = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:fs.f_mntfromname length:strlen(fs.f_mntfromname)];
		result = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:fs.f_fstypename], NSWorkspace_RBfstypename, [[NSFileManager defaultManager] stringWithFileSystemRepresentation:fs.f_mntonname length:strlen(fs.f_mntonname)], NSWorkspace_RBmntonname, nil];
		const char* devstring = "/dev/";
		size_t devstringlen = 5;
		if (strncmp(fs.f_mntfromname,devstring,devstringlen)==0) {
			// For a local volume,get the IO registry tree and search it for further info.
			mach_port_t masterPort = 0;
			io_iterator_t mediaIterator = 0;
			kern_return_t kernResult = IOMasterPort(bootstrap_port,&masterPort);
			if (kernResult==KERN_SUCCESS) {
				CFMutableDictionaryRef classesToMatch = IOBSDNameMatching(masterPort,0,&fs.f_mntfromname[devstringlen]);
				if (classesToMatch) {
					kernResult = IOServiceGetMatchingServices(masterPort,classesToMatch,&mediaIterator);
					if ((kernResult==KERN_SUCCESS)&&mediaIterator) {
						io_object_t firstMedia = 0;
						while ((firstMedia = IOIteratorNext(mediaIterator))) {
							NSString* stuff = CheckParents(firstMedia,nil,result);
							if (stuff) {
								[result setObject:stuff forKey:NSWorkspace_RBdeviceinfo];
							}
							IOObjectRelease(firstMedia);
						}
					}
				}
			}
			if (mediaIterator) {
				IOObjectRelease(mediaIterator);
			}
			if (masterPort) {
				mach_port_deallocate(mach_task_self(),masterPort);
			}
		}
		[result setObject:from forKey:NSWorkspace_RBmntfromname];
	}
	return result;
}

@end
