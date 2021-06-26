//
//  SPUAppcastItemStateResolver+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/20/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#ifndef SPUAppcastItemStateResolver_Private_h
#define SPUAppcastItemStateResolver_Private_h

NS_ASSUME_NONNULL_BEGIN

@interface SPUAppcastItemStateResolver ()

- (SPUAppcastItemState *)resolveStateWithInformationalUpdateVersions:(NSSet<NSString *> * _Nullable)informationalUpdateVersions minimumOperatingSystemVersion:(NSString * _Nullable)minimumOperatingSystemVersion maximumOperatingSystemVersion:(NSString * _Nullable)maximumOperatingSystemVersion minimumAutoupdateVersion:(NSString * _Nullable)minimumAutoupdateVersion criticalUpdateDictionary:(NSDictionary * _Nullable)criticalUpdateDictionary;

+ (BOOL)isMinimumAutoupdateVersionOK:(NSString * _Nullable)minimumAutoupdateVersion hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator;

@end

NS_ASSUME_NONNULL_END

#endif /* SPUAppcastItemStateResolver_Private_h */
