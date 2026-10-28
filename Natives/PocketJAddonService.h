#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^PJAddonVersions)(NSArray<NSDictionary *> * _Nullable versions, NSError * _Nullable error);
@interface PocketJAddonService : NSObject
- (instancetype)initWithCurseForgeKey:(NSString *)key;
- (void)versionsForProvider:(NSString *)provider project:(NSString *)project
                 minecraft:(NSString *)minecraft loader:(NSString *)loader
            compatibleOnly:(BOOL)compatible completion:(PJAddonVersions)completion;
- (void)identifyFile:(NSString *)path record:(NSDictionary *)record
         completion:(void (^)(NSDictionary * _Nullable identity, NSError * _Nullable error))completion;
- (void)resolveDownload:(NSDictionary *)file completion:(void (^)(NSDictionary * _Nullable descriptor, NSError * _Nullable error))completion;
/// Resolves required/optional edges with per-request cycle/size/depth limits.
/// Result excludes already installed exact versions and annotates replacements.
- (void)dependencyPlanForFile:(NSDictionary *)file installed:(NSArray<NSDictionary *> *)installed
                  minecraft:(NSString *)minecraft loader:(NSString *)loader
                 completion:(PJAddonVersions)completion;
+ (uint32_t)curseForgeFingerprint:(NSData *)data;
@end
NS_ASSUME_NONNULL_END
