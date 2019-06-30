//
//  SPUDownloadData.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloadData.h"

#import "SUOperatingSystem.h"

#include "AppKitPrevention.h"

static NSString *SPUDownloadDataKey = @"SPUDownloadData";
static NSString *SPUDownloadTextEncodingKey = @"SPUDownloadTextEncoding";
static NSString *SPUDownloadMIMETypeKey = @"SPUDownloadMIMEType";

@implementation SPUDownloadData

@synthesize data = _data;
@synthesize textEncodingName = _textEncodingName;
@synthesize MIMEType = _MIMEType;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithData:(NSData *)data textEncodingName:(NSString * _Nullable)textEncodingName MIMEType:(NSString *)MIMEType
{
    self = [super init];
    if (self != nil) {
        _data = data;
        _textEncodingName = textEncodingName;
        _MIMEType = MIMEType;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.data forKey:SPUDownloadDataKey];
    
    if (self.textEncodingName != nil) {
        [coder encodeObject:self.textEncodingName forKey:SPUDownloadTextEncodingKey];
    }
    
    if (self.MIMEType != nil) {
        [coder encodeObject:self.MIMEType forKey:SPUDownloadMIMETypeKey];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    if (SUAVAILABLE(10, 8)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        NSData *data = [decoder decodeObjectOfClass:[NSData class] forKey:SPUDownloadDataKey];
        if (data == nil) {
            return nil;
        }

        NSString *textEncodingName = [decoder decodeObjectOfClass:[NSString class] forKey:SPUDownloadTextEncodingKey];

        NSString *MIMEType = [decoder decodeObjectOfClass:[NSString class] forKey:SPUDownloadMIMETypeKey];
#pragma clang diagnostic pop

        return [self initWithData:data textEncodingName:textEncodingName MIMEType:MIMEType];
    } else {
        abort(); // Not used on 10.7
    }
}

@end
