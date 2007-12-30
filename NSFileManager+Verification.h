//
//  NSFileManager+Verification.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef NSFILEMANAGER_PLUS_VERIFICATION_H
#define NSFILEMANAGER_PLUS_VERIFICATION_H

// For the paranoid folks!
@interface NSFileManager (SUVerification)
- (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString;
@end

#endif
