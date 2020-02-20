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

// Pass YES to performingPrevalidation if archive validation must be done immediately, before extraction
- (instancetype)initWithDownloadPath:(NSString *)downloadPath signatures:(SUSignatures *)signatures host:(SUHost *)host performingPrevalidation:(BOOL)performingPrevalidation;

// Indicates whether we can perform (post) validation later
@property (nonatomic, readonly) BOOL canValidate;

// precondition: validation must be possible (see -canValidate)
// This is "post" validation, after an archive has been extracted
- (BOOL)validateWithUpdateDirectory:(NSString *)updateDirectory;

@end
