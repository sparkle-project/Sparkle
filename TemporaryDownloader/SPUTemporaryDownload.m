//
//  SPUTemporaryDownload.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUTemporaryDownload.h"

static NSString *SPUTemporaryDownloadDataKey = @"SPUTemporaryDownloadData";
static NSString *SPUTemporaryDownloadTextEncodingKey = @"SPUTemporaryDownloadTextEncoding";
static NSString *SPUTemporaryDownloadMIMETypeKey = @"SPUTemporaryDownloadMIMEType";

@implementation SPUTemporaryDownload

@synthesize data = _data;
@synthesize textEncoding = _textEncoding;
@synthesize MIMEType = _MIMEType;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithData:(NSData *)data textEncoding:(NSString * _Nullable)textEncoding MIMEType:(NSString *)MIMEType
{
    self = [super init];
    if (self != nil) {
        _data = data;
        _textEncoding = textEncoding;
        _MIMEType = MIMEType;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.data forKey:SPUTemporaryDownloadDataKey];
    
    if (self.textEncoding != nil) {
        [coder encodeObject:self.textEncoding forKey:SPUTemporaryDownloadTextEncodingKey];
    }
    
    if (self.MIMEType != nil) {
        [coder encodeObject:self.MIMEType forKey:SPUTemporaryDownloadMIMETypeKey];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    NSData *data = [decoder decodeObjectOfClass:[NSData class] forKey:SPUTemporaryDownloadDataKey];
    if (data == nil) {
        return nil;
    }
    
    NSString *textEncoding = [decoder decodeObjectOfClass:[NSString class] forKey:SPUTemporaryDownloadTextEncodingKey];
    NSString *MIMEType = [decoder decodeObjectOfClass:[NSString class] forKey:SPUTemporaryDownloadMIMETypeKey];
    
    return [self initWithData:data textEncoding:textEncoding MIMEType:MIMEType];
}

@end
