//
//  SUDSAVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUDSAVERIFIER_H
#define SUDSAVERIFIER_H

// For the paranoid folks!
@interface SUDSAVerifier : NSObject {}
+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString;
@end

#endif
