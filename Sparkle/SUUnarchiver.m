//
//  SUUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUUnarchiver.h"
#import "SUUnarchiver_Private.h"

@interface SUUnarchiver ()
@property (strong) void (^completionBlock)(NSError * _Nullable);
@end

@implementation SUUnarchiver

@synthesize archivePath;
@synthesize updateHostBundlePath;
@synthesize delegate;
@synthesize decryptionPassword;
@synthesize completionBlock;

+ (SUUnarchiver *)unarchiverForPath:(NSString *)path updatingHostBundlePath:(NSString *)hostPath withPassword:(NSString *)decryptionPassword
{
    for (id current in [self unarchiverImplementations]) {
        if ([current canUnarchivePath:path]) {
            return [[current alloc] initWithPath:path hostBundlePath:hostPath password:decryptionPassword];
        }
    }
    return nil;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

- (void)unarchiveWithCompletionBlock:(void (^_Nonnull)(NSError * _Nullable))block {
    self.completionBlock = block;
}

- (instancetype)initWithPath:(NSString *)path hostBundlePath:(NSString *)hostPath password:(NSString *)password
{
    if ((self = [super init]))
    {
        archivePath = [path copy];
        updateHostBundlePath = hostPath;
        decryptionPassword = password;
    }
    return self;
}

+ (BOOL)canUnarchivePath:(NSString *)__unused path
{
    return NO;
}

+ (BOOL)unsafeIfArchiveIsNotValidated
{
    return NO;
}

- (void)notifyDelegateOfProgress:(double)progress
{
    if ([self.delegate respondsToSelector:@selector(unarchiver:extractedProgress:)]) {
        [self.delegate unarchiver:self extractedProgress:progress];
    }
}

- (void)unarchiverDidFinish
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.completionBlock(nil);
    });
}

- (void)unarchiverDidFail:(NSError *)reason
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) forKey:NSLocalizedDescriptionKey];
    if (reason) {
        [userInfo setObject:reason forKey:NSUnderlyingErrorKey];
    }

    NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:userInfo];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.completionBlock(error);
    });
}

static NSMutableArray *gUnarchiverImplementations;

+ (void)registerImplementation:(Class)implementation
{
    if (!gUnarchiverImplementations) {
        gUnarchiverImplementations = [[NSMutableArray alloc] init];
    }
    [gUnarchiverImplementations addObject:implementation];
}

+ (NSArray *)unarchiverImplementations
{
    return [NSArray arrayWithArray:gUnarchiverImplementations];
}

@end
