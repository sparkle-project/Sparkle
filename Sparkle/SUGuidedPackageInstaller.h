//
//  SUGuidedPackageInstaller.h
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

/*!
# Sparkle Guided Installations

A guided installation allows Sparkle to download and install a package (pkg) or multi-package (mpkg) without user interaction.

A guided installation occurs when Sparkle finds a `.sparkle_guide.plist` in the root of the download; the file contains the relative path of the installer package to install.

The file must be a property list and have a dictionary root. The only required key pair value is `package`.

The `package` key value pair must be set to a relative path to the package or multi-package to install. The path is relative to the guide file.

Example Contents of Sparkle Guide file:

	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>package</key>
		<string>My Package.pkg</string>
	</dict>
	</plist>

Example Path of Sparkle Guide file:

	/Volumes/MyUpdateDiskImage/.sparkle_guide.plist

The installer package is installed using Mac OS X's built-in command line installer, `/usr/sbin/installer`. No installation interface is shown to the user.

A guided installation can be started by applications other than the application being replaced. This is particularly useful where helper applications or agents are used.

## Notes
This method has been tested and successfully deployed on Mac OS X 10.4 - 10.8.

## To Do
- Replace the use of `AuthorizationExecuteWithPrivilegesAndWait`. This method remains because it is well supported and tested. Ideally a helper tool or XPC would be used.
*/

#ifndef SUGUIDEDPACKAGEINSTALLER_H
#define SUGUIDEDPACKAGEINSTALLER_H

#import "Sparkle.h"
#import "SUInstaller.h"

extern NSString* SUInstallerGuidedInstallerFilename; // default filename for guided installer property list

@interface SUGuidedPackageInstaller : SUInstaller { }
/*! Search for and return any installer guide */
+ (NSString *)installerGuideWithinUpdateFolder:(NSString *)updateFolder;

/*! Perform the guided installation */
+ (void)performInstallationToPath:(NSString *)path fromPath:(NSString *)installerGuide host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator;
@end

#endif
