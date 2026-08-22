#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StikDebugEngine : NSObject

+ (instancetype)sharedEngine;
@property(nonatomic, readonly) NSString *pairingFilePath;
@property(nonatomic, readonly) BOOL hasPairingFile;

- (BOOL)importPairingFileAtURL:(NSURL *)URL error:(NSError **)error;
- (void)enableJITForCurrentProcessWithCompletion:
    (void (^)(BOOL success, NSString *message))completion;

@end

NS_ASSUME_NONNULL_END
