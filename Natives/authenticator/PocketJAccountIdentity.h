#import <Foundation/Foundation.h>
@interface PocketJAccountIdentity : NSObject
+ (NSString *)storageKey:(NSDictionary *)account;
+ (NSString *)normalizedServer:(NSString *)server;
@end
