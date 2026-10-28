#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// On-disk state belongs to the instance, never to a display name or table row.
@interface PocketJModStore : NSObject
@property(nonatomic, readonly) NSString *instancePath;
@property(nonatomic, readonly) NSString *modsPath;
@property(nonatomic, readonly) NSString *instanceID;
- (instancetype)initWithInstancePath:(NSString *)path;
/// Scan on a worker queue. No network access; unknown JARs remain manageable.
- (NSArray<NSDictionary *> *)scan:(NSError **)error;
- (BOOL)setEnabled:(BOOL)enabled file:(NSString *)file error:(NSError **)error;
- (BOOL)deleteFiles:(NSArray<NSString *> *)files error:(NSError **)error;
- (BOOL)renameFile:(NSString *)file to:(NSString *)name error:(NSError **)error;
- (BOOL)annotateFile:(NSString *)file values:(NSDictionary *)values error:(NSError **)error;
- (nullable NSDictionary *)recordForFile:(NSString *)file;
/// Validate first; atomically replace only after the new JAR is complete.
/// Enabled/disabled state and stable record ID survive updates/version changes.
- (BOOL)installJar:(NSURL *)source fileName:(NSString *)name
     replacingFile:(nullable NSString *)oldName metadata:(NSDictionary *)metadata
             error:(NSError **)error;
+ (BOOL)isSafeFileName:(NSString *)name;
+ (nullable NSString *)sha1AtPath:(NSString *)path;
+ (BOOL)validateJarAtPath:(NSString *)path error:(NSError **)error;
+ (NSArray<NSDictionary *> *)filterMods:(NSArray<NSDictionary *> *)mods query:(NSString *)query;
@end
NS_ASSUME_NONNULL_END
