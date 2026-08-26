#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PocketJUpdateAvailabilityDidChangeNotification;

@interface PocketJUpdateChecker : NSObject
@property(class, nonatomic, readonly) PocketJUpdateChecker *shared;
@property(nonatomic, readonly, nullable) NSDictionary *availableRelease;
- (void)checkForUpdates;
- (void)checkForUpdatesWithCompletion:(void (^ _Nullable)(NSDictionary * _Nullable release,
                                                           NSError * _Nullable error))completion;
- (void)dismissAvailableRelease;
@end

NS_ASSUME_NONNULL_END
