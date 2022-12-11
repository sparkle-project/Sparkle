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

NS_ASSUME_NONNULL_BEGIN

@interface SUUpdateValidator : NSObject

- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host __attribute__((objc_direct));

// This is "pre" validation, before the archive has been extracted
- (BOOL)validateDownloadPathWithError:(NSError **)error __attribute__((objc_direct));

// This is "post" validation, after an archive has been extracted
- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory error:(NSError **)error __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
