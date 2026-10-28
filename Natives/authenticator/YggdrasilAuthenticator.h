#import "BaseAuthenticator.h"
@interface YggdrasilAuthenticator : BaseAuthenticator
+ (NSString *)normalizedServer:(NSString *)server;
+ (NSString *)agentPath;
+ (void)authenticateServer:(NSString *)server username:(NSString *)username password:(NSString *)password
                completion:(void (^)(NSDictionary *response, NSString *resolvedServer, NSError *error))completion;
- (void)selectProfile:(NSDictionary *)profile callback:(Callback)callback;
+ (void)clearTokenDataOfProfile:(NSString *)profile;
@end
