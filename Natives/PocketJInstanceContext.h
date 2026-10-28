#import <Foundation/Foundation.h>
@interface PocketJInstanceContext : NSObject
@property(nonatomic,readonly) NSString *minecraftVersion;
@property(nonatomic,readonly) NSString *loader;
@property(nonatomic,readonly) NSDictionary *profile;
- (instancetype)initWithInstancePath:(NSString *)path;
@end
