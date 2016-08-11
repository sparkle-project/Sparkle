//
//  SPUTemporaryDownload.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPUTemporaryDownload : NSObject <NSSecureCoding>

- (instancetype)initWithData:(NSData *)data textEncoding:(NSString * _Nullable)textEncoding MIMEType:(NSString * _Nullable)MIMEType;

@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly, nullable, copy) NSString *textEncoding;
@property (nonatomic, readonly, nullable, copy) NSString *MIMEType;

@end

NS_ASSUME_NONNULL_END
