#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StikDebugEngine : NSObject

+ (instancetype)sharedEngine;
@property(nonatomic, readonly) NSString *pairingFilePath;
@property(nonatomic, readonly) NSString *documentsPairingFilePath;
@property(nonatomic, readonly) BOOL hasPairingFile;

- (BOOL)importPairingFileAtURL:(NSURL *)URL error:(NSError **)error;
- (BOOL)synchronizePairingFileFromDocuments:(NSError **)error;
- (BOOL)deletePairingFile:(NSError **)error;
- (nullable NSURL *)exportablePairingFileURL:(NSError **)error;
- (void)checkLocalDevVPNWithCompletion:(void (^)(BOOL connected))completion;
- (void)enableJITForCurrentProcessWithCompletion:
    (void (^)(BOOL success, NSString *message))completion;

@end

NS_ASSUME_NONNULL_END
