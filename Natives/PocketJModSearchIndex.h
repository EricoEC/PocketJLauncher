#import <Foundation/Foundation.h>
@interface PocketJModSearchIndex : NSObject
+ (instancetype)shared;
- (NSString *)onlineQuery:(NSString *)query installed:(NSArray<NSDictionary *> *)installed;
/// Extensible offline index, not a network translation service. Accepts CSV
/// aliases,query or HMCL-style mod.csv factual fields supplied by the user.
- (BOOL)importCSV:(NSURL *)url error:(NSError **)error;
+ (NSArray<NSArray<NSString *> *> *)parseCSV:(NSString *)text;
@end
