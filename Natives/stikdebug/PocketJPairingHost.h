#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const PocketJPairingHostDidChangeNotification;
typedef NS_ENUM(NSInteger, PocketJPairingState) {
    PocketJPairingStateIdle, PocketJPairingStateWorking,
    PocketJPairingStateSucceeded, PocketJPairingStateFailed, PocketJPairingStateCancelled
};

@interface PocketJPairingHost : NSObject
+ (instancetype)sharedHost;
+ (BOOL)isSupported;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) PocketJPairingState state;
@property(nonatomic, readonly, copy) NSString *status;
@property(nonatomic, readonly, copy, nullable) NSString *PIN;
- (void)start;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
