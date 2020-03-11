//
//  SUUpdateValidator.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUHost;
@class SUSignatures;

@interface SUUpdateValidator : NSObject

- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host;

// This is "pre" validation, before the archive has been extracted
- (BOOL)validateDownloadPath;

// This is "post" validation, after an archive has been extracted
- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory;

@end
