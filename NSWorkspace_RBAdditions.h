//
//  NSWorkspace_RBAdditions.h
//  PathProps
//
//  Created by Rainer Brockerhoff on 10/04/2007.
//  Copyright 2007 Rainer Brockerhoff. All rights reserved.
//

#ifndef NSWORKSPACE_RBADDITIONS_H
#define NSWORKSPACE_RBADDITIONS_H


extern NSString* NSWorkspace_RBfstypename;
extern NSString* NSWorkspace_RBmntonname;
extern NSString* NSWorkspace_RBmntfromname;
extern NSString* NSWorkspace_RBdeviceinfo;
extern NSString* NSWorkspace_RBimagefilepath;
extern NSString* NSWorkspace_RBconnectiontype;
extern NSString* NSWorkspace_RBpartitionscheme;
extern NSString* NSWorkspace_RBserverURL;

@interface NSWorkspace (NSWorkspace_RBAdditions)

// This method will return nil if the input path is invalid. Otherwise, the returned NSDictionary may contain
// the following keys:
//- NSWorkspace_RBfstypename: will always be present.Shows the filesystem type (usually "hfs"), from statfs.
//- NSWorkspace_RBmntonname: will always be present. Shows the volume mount point.
//- NSWorkspace_RBmntfromname: will always be present. Shows the BSD device path for local volumes; info for
//		remote volumes depends on the filesystem type.
//- NSWorkspace_RBconnectiontype: should always be present for local volumes. Shows the connection type ("SATA", "USB", etc.).
//- NSWorkspace_RBpartitionscheme: should always be present for local volumes. Shows the partition scheme.
//- NSWorkspace_RBdeviceinfo: should always be present for local volumes. Shows some information about the
//		physical device; varies widely.
//- NSWorkspace_RBimagefilepath: should be present for disk images only. Shows the path of the disk image file.
//- NSWorkspace_RBserverURL: should be present for remote volumes only. Shows the server URL.

- (NSDictionary*)propertiesForPath:(NSString*)path;

@end

#endif
