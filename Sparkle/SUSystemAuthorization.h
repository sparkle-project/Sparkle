//
//  SUSystemAuthorization.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ServiceManagement/SMLoginItem.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SUNeedsSystemAuthorizationAccess(NSString *path, NSString *installationType, BOOL * _Nullable preflighted);

NS_ASSUME_NONNULL_END
