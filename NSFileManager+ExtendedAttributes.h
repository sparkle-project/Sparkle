//
//  NSFileManager+ExtendedAttributes.h
//  Sparkle
//
//  Created by Mark Mentovai on 2008-01-22.
//  Copyright 2008 Mark Mentovai.  All rights reserved.
//

#ifndef NSFILEMANAGER_PLUS_EXTENDEDATTRIBUTES
#define NSFILEMANAGER_PLUS_EXTENDEDATTRIBUTES

#import <Cocoa/Cocoa.h>

@interface NSFileManager (ExtendedAttributes)

// Wraps the removexattr system call, allowing an AppKit-style NSString* to
// be used for the pathname argument.  Note that the order of the arguments
// has changed from what removexattr accepts, so that code reads more
// naturally.
//
// removexattr is only available on Mac OS X 10.4 ("Tiger") and later.  If
// built with an SDK that includes removexattr, this method will link against
// removexattr directly.  When using earlier SDKs, this method will dynamically
// look up the removexattr symbol at runtime.  If the symbol is not present,
// as will be the case when running on 10.3, this method returns -1 and sets
// errno to ENOSYS.
- (int)removeXAttr:(const char*)name
          fromFile:(NSString*)file
           options:(int)options;

// Removes the directory tree rooted at |root| from the file quarantine.
// The quarantine was introduced on Mac OS X 10.5 and is described at:
//
//   http://developer.apple.com/releasenotes/Carbon/RN-LaunchServices/index.html
//#apple_ref/doc/uid/TP40001369-DontLinkElementID_2
//
// If |root| is not a directory, then it alone is removed from the quarantine.
// Symbolic links, including |root| if it is a symbolic link, will not be
// traversed.
//
// Ordinarily, the quarantine is managed by calling LSSetItemAttribute
// to set the kLSItemQuarantineProperties attribute to a dictionary specifying
// the quarantine properties to be applied.  However, it does not appear to be
// possible to remove an item from the quarantine directly through any public
// Launch Services calls.  Instead, this method takes advantage of the fact
// that the quarantine is implemented in part by setting an extended attribute,
// "com.apple.quarantine", on affected files.  Removing this attribute is
// sufficient to remove files from the quarantine.
- (void)releaseFromQuarantine:(NSString*)root;

@end

#endif
