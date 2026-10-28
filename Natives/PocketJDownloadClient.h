#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^PJDownloadCompletion)(NSURL * _Nullable file, NSError * _Nullable error);
/// Shared transport for add-ons. Completion/progress always arrive on main.
/// Descriptor is JSON/property-list safe and never contains provider API keys.
@interface PocketJDownloadClient : NSObject
+ (instancetype)shared;
- (NSString *)download:(NSDictionary *)descriptor instanceID:(NSString *)identity
              progress:(nullable void (^)(double fraction))progress
            completion:(PJDownloadCompletion)completion;
- (void)pause:(NSString *)taskID;
- (void)cancel:(NSString *)taskID;
+ (BOOL)verifyFile:(NSURL *)file descriptor:(NSDictionary *)descriptor error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
