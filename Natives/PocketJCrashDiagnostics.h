#import <Foundation/Foundation.h>
@interface PocketJCrashDiagnostics : NSObject
/// Heuristic hints, not a proven root cause; never changes game settings.
+ (NSDictionary<NSString *,NSString *> *)analyze:(NSString *)log;
+ (NSString *)tailAtPath:(NSString *)path limit:(NSUInteger)limit;
@end
