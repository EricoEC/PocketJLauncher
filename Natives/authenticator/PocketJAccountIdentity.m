#import "PocketJAccountIdentity.h"
#include <CommonCrypto/CommonDigest.h>
@implementation PocketJAccountIdentity
+ (NSString *)normalizedServer:(NSString *)input {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *value=[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![value containsString:@"://"]) value=[@"https://" stringByAppendingString:value];
    NSURLComponents *parts=[NSURLComponents componentsWithString:value];
    if (![parts.scheme.lowercaseString isEqual:@"https"] || !parts.host.length || parts.user.length || parts.password.length || parts.query.length || parts.fragment.length) return nil;
    parts.scheme=@"https"; parts.host=parts.host.lowercaseString; if ([parts.port isEqual:@443]) parts.port=nil;
    if (![parts.path hasSuffix:@"/"]) parts.path=[parts.path stringByAppendingString:@"/"];
    return parts.URL.absoluteString;
}
+ (NSString *)storageKey:(NSDictionary *)account {
    if ([account[@"accountType"] isEqual:@"yggdrasil"]) {
        NSString *server=[self normalizedServer:account[@"authServer"]] ?: @"";
        NSData *data=[server dataUsingEncoding:NSUTF8StringEncoding]; unsigned char bytes[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
        NSMutableString *host=[NSMutableString string]; for (NSUInteger i=0;i<sizeof(bytes);i++) [host appendFormat:@"%02x",bytes[i]];
        NSString *profile=[account[@"profileId"] isKindOfClass:NSString.class] ? [account[@"profileId"] stringByReplacingOccurrencesOfString:@"-" withString:@""]:@"";
        profile=profile.lowercaseString;
        if (profile.length!=32 || [profile rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound) profile=@"invalid-profile";
        return [NSString stringWithFormat:@"yggdrasil__%@__%@",host,profile];
    }
    BOOL microsoft=[account[@"expiresAt"] longLongValue]>0 || [account[@"xuid"] length]>0 || [account[@"xboxGamertag"] length]>0;
    NSString *identity=microsoft ? (account[@"xuid"] ?: account[@"profileId"] ?: account[@"username"]):account[@"username"];
    if (!identity.length) identity=NSUUID.UUID.UUIDString;
    NSString *safe=[[identity componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@"-"];
    return [NSString stringWithFormat:@"%@__%@",microsoft ? @"microsoft":@"local",safe];
}
@end
