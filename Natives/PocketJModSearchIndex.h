#import <Foundation/Foundation.h>
@interface PocketJModSearchIndex : NSObject
+ (instancetype)shared;
- (NSString *)onlineQuery:(NSString *)query installed:(NSArray<NSDictionary *> *)installed;
@end
