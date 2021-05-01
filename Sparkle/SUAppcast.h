//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem;
SU_EXPORT @interface SUAppcast : NSObject

- (nullable instancetype)initWithXMLData:(NSData *)xmlData relativeToURL:(NSURL *)relativeURL error:(NSError * __autoreleasing *)error;

- (SUAppcast *)copyByFilteringItems:(BOOL (^)(SUAppcastItem *))filterBlock;

@property (readonly, copy, nullable) NSArray<SUAppcastItem *> *items;

@end

NS_ASSUME_NONNULL_END

#endif
