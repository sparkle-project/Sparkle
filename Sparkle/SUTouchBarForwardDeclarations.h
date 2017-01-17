//
//  SUTouchBarForwardDeclarations.h
//  Sparkle
//
//  Created by Yuxin Wang on 18/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

// Once Sparkle no longer supports OSX 10.12.0, this file can be deleted.

#import <Foundation/Foundation.h>

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101201

NS_ASSUME_NONNULL_BEGIN

@class NSTouchBar;
@class NSTouchBarItem;
@class NSCustomTouchBarItem;

typedef NSString * NSTouchBarItemIdentifier NS_EXTENSIBLE_STRING_ENUM;
typedef NSString * NSTouchBarCustomizationIdentifier NS_EXTENSIBLE_STRING_ENUM;

@protocol NSTouchBarDelegate;

NS_CLASS_AVAILABLE_MAC(10_12_2)
@interface NSTouchBar : NSObject <NSCoding>

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_DESIGNATED_INITIALIZER;

@property (copy, nullable) NSTouchBarCustomizationIdentifier customizationIdentifier;
@property (copy) NSArray<NSTouchBarItemIdentifier> *customizationAllowedItemIdentifiers;
@property (copy) NSArray<NSTouchBarItemIdentifier> *customizationRequiredItemIdentifiers;
@property (copy) NSArray<NSTouchBarItemIdentifier> *defaultItemIdentifiers;
@property (copy, readonly) NSArray<NSTouchBarItemIdentifier> *itemIdentifiers;
@property (copy, nullable) NSTouchBarItemIdentifier principalItemIdentifier;
@property (copy, nullable) NSTouchBarItemIdentifier escapeKeyReplacementItemIdentifier;
@property (copy) NSSet<NSTouchBarItem *> *templateItems;
@property (nullable, weak) id <NSTouchBarDelegate> delegate;
- (nullable __kindof NSTouchBarItem *)itemForIdentifier:(NSTouchBarItemIdentifier)identifier;
@property (readonly, getter=isVisible) BOOL visible;

@end

@protocol NSTouchBarDelegate<NSObject>
@optional
- (nullable NSTouchBarItem*)touchBar:(NSTouchBar*)touchBar
               makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier;
@end

typedef float NSTouchBarItemPriority _NS_TYPED_EXTENSIBLE_ENUM;

NS_CLASS_AVAILABLE_MAC(10_12_2)
@interface NSTouchBarItem : NSObject <NSCoding>

- (instancetype)initWithIdentifier:(NSTouchBarItemIdentifier)identifier NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (readonly, copy) NSTouchBarItemIdentifier identifier;
@property NSTouchBarItemPriority visibilityPriority;
@property (readonly, nullable) NSView *view;
@property (readonly, nullable) NSViewController *viewController;
@property (readonly, copy) NSString *customizationLabel;
@property (readonly, getter=isVisible) BOOL visible;

@end

NS_CLASS_AVAILABLE_MAC(10_12_2)
@interface NSCustomTouchBarItem : NSTouchBarItem

@property (readwrite, strong) __kindof NSView *view;
@property (readwrite, strong, nullable) __kindof NSViewController *viewController;
@property (readwrite, copy, null_resettable) NSString *customizationLabel;

@end

NS_ASSUME_NONNULL_END

#else

// When compiling against the 10.12.1 SDK or later, just provide forward
// declarations to suppress the partial availability warnings.

@class NSTouchBar;
@protocol NSTouchBarDelegate;
@class NSTouchBarItem;
@class NSCustomTouchBarItem;

#endif
