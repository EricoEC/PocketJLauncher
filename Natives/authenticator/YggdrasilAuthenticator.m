#include "PocketJEnvironment.h"
#import "YggdrasilAuthenticator.h"
#import "PocketJAccountIdentity.h"
#import "../PocketJDownloadClient.h"
#import "../utils.h"
#import <Security/Security.h>

static NSError *PJAuthError(NSString *message) { return [NSError errorWithDomain:@"PocketJ.Yggdrasil" code:1 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(message ?: @"Authentication failed.",nil)}]; }
@interface PJYggdrasilTransport : NSObject <NSURLSessionTaskDelegate> @end
@implementation PJYggdrasilTransport
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    NSURL *original=task.originalRequest.URL, *target=request.URL;
    BOOL sameOrigin=[original.host.lowercaseString isEqual:target.host.lowercaseString] && [target.scheme.lowercaseString isEqual:@"https"] && [(original.port ?: @443) isEqual:(target.port ?: @443)];
    completion(sameOrigin && [request.HTTPMethod isEqual:task.originalRequest.HTTPMethod] ? request:nil);
}
@end
@implementation YggdrasilAuthenticator
+ (NSString *)normalizedServer:(NSString *)input { return [PocketJAccountIdentity normalizedServer:input]; }
+ (NSString *)agentPath { return [[@(PocketJGetEnv("POCKETJ_HOME")) stringByAppendingPathComponent:@"authlib-injector"] stringByAppendingPathComponent:@"authlib-injector-1.2.7.jar"]; }
+ (void)ensureAgent:(void (^)(NSError *))completion {
    NSDictionary *descriptor=@{@"url":@"https://authlib-injector.yushi.moe/artifact/55/authlib-injector-1.2.7.jar",@"filename":@"authlib-injector-1.2.7.jar",@"hashes":@{@"sha256":@"eaf14bc5acffc7d885bd5bd5942b99f36d6299302beae356b2fc5807fe42652b"},@"archive":@YES};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        if ([PocketJDownloadClient verifyFile:[NSURL fileURLWithPath:self.agentPath] descriptor:descriptor error:nil]) { dispatch_async(dispatch_get_main_queue(),^{ completion(nil); }); return; }
        [PocketJDownloadClient.shared download:descriptor instanceID:@"authlib-injector-build-55" progress:nil completion:^(NSURL *file,NSError *error) {
            if (error) { completion(error); return; }
            NSString *target=self.agentPath; NSFileManager *fm=NSFileManager.defaultManager;
            NSError *failure=nil; [fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure];
            NSString *stage=[target stringByAppendingString:@".part"]; [fm removeItemAtPath:stage error:nil];
            if (!failure) [fm copyItemAtPath:file.path toPath:stage error:&failure];
            if (!failure) {
                if ([fm fileExistsAtPath:target]) [fm replaceItemAtURL:[NSURL fileURLWithPath:target] withItemAtURL:[NSURL fileURLWithPath:stage] backupItemName:nil options:0 resultingItemURL:nil error:&failure];
                else [fm moveItemAtPath:stage toPath:target error:&failure];
            }
            [fm removeItemAtURL:file error:nil]; completion(failure);
        }];
    });
}
+ (void)request:(NSString *)server endpoint:(NSString *)endpoint body:(NSDictionary *)body completion:(void (^)(NSDictionary *, NSError *))completion {
    NSURL *url=[NSURL URLWithString:endpoint relativeToURL:[NSURL URLWithString:server]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url]; request.HTTPMethod=@"POST"; request.timeoutInterval=20;
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURLSession *session=[NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:[PJYggdrasilTransport new] delegateQueue:nil];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        NSDictionary *json=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if (![json isKindOfClass:NSDictionary.class]) json=nil;
        NSInteger status=[(NSHTTPURLResponse *)response statusCode];
        if (!error && (status<200 || status>=300 || !json)) error=PJAuthError(json[@"errorMessage"] ?: @"The authentication server returned an invalid response.");
        // Never log request bodies, passwords or access/client tokens.
        [session finishTasksAndInvalidate];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json,error); });
    }] resume];
}
+ (void)authenticateServer:(NSString *)server username:(NSString *)username password:(NSString *)password completion:(void (^)(NSDictionary *,NSString *,NSError *))completion {
    NSString *normalized=[self normalizedServer:server];
    if (!normalized || !username.length || !password.length) { completion(nil,nil,PJAuthError(localize(@"请输入 HTTPS 认证地址、用户名和密码。",nil))); return; }
    // Discover the advertised API root before sending credentials. The resolved
    // origin is shown to the user by the login form; cross-origin ALI is rejected
    // to avoid silently forwarding a password to another server.
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:normalized]]; request.timeoutInterval=15;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        NSString *ali=[(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"X-Authlib-Injector-API-Location"];
        NSURL *resolved=ali.length ? [NSURL URLWithString:ali relativeToURL:response.URL].absoluteURL : [NSURL URLWithString:normalized];
        NSString *root=[self normalizedServer:resolved.absoluteString];
        NSURL *original=[NSURL URLWithString:normalized];
        if (error || !root || ![resolved.host.lowercaseString isEqual:original.host.lowercaseString] || ![(resolved.port ?: @443) isEqual:(original.port ?: @443)]) { dispatch_async(dispatch_get_main_queue(),^{ completion(nil,nil,error ?: PJAuthError(@"The authentication API redirects to a different origin. Enter that HTTPS API address explicitly.")); }); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self request:root endpoint:@"authserver/authenticate" body:@{@"agent":@{@"name":@"Minecraft",@"version":@1},@"username":username,@"password":password,@"clientToken":NSUUID.UUID.UUIDString,@"requestUser":@YES} completion:^(NSDictionary *json,NSError *error) { completion(json,root,error); }];
        });
    }] resume];
}
+ (NSMutableDictionary *)query:(NSString *)profile {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"PocketJ.Yggdrasil",(__bridge id)kSecAttrAccount:profile} mutableCopy];
}
+ (NSDictionary *)tokenDataOfProfile:(NSString *)profile {
    NSMutableDictionary *query=[self query:profile]; query[(__bridge id)kSecReturnData]=@YES; query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef result=NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query,&result)!=errSecSuccess) return nil;
    NSData *data=CFBridgingRelease(result); id tokens=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [tokens isKindOfClass:NSDictionary.class] ? tokens:nil;
}
+ (void)clearTokenDataOfProfile:(NSString *)profile { SecItemDelete((__bridge CFDictionaryRef)[self query:profile]); }
- (BOOL)saveChanges {
    NSString *key=[BaseAuthenticator storageKeyForAuthData:self.authData]; self.authData[@"xuid"]=key;
    NSDictionary *tokens=@{@"accessToken":self.authData[@"accessToken"] ?: @"",@"clientToken":self.authData[@"clientToken"] ?: @""};
    if (![tokens[@"accessToken"] length]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:tokens options:0 error:nil];
    NSMutableDictionary *query=[YggdrasilAuthenticator query:key];
    NSDictionary *values=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)values);
    if (status==errSecItemNotFound) { [query addEntriesFromDictionary:values]; status=SecItemAdd((__bridge CFDictionaryRef)query,NULL); }
    if (status!=errSecSuccess) return NO;
    [self.authData removeObjectsForKeys:@[@"accessToken",@"clientToken",@"password",@"availableProfiles",@"boundProfileID"]];
    return [super saveChanges];
}
- (void)selectProfile:(NSDictionary *)profile callback:(Callback)callback {
    if (![profile[@"id"] isKindOfClass:NSString.class] || ![profile[@"name"] isKindOfClass:NSString.class]) { callback(PJAuthError(@"Invalid Minecraft profile."),NO); return; }
    NSString *identifier=[profile[@"id"] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (identifier.length!=32 || [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location!=NSNotFound) { callback(PJAuthError(@"Invalid Minecraft profile."),NO); return; }
    NSString *bound=[self.authData[@"boundProfileID"] isKindOfClass:NSString.class] ? self.authData[@"boundProfileID"]:@"";
    if (bound.length) {
        // authenticate may already bind a single-profile account. Sending a
        // second selectedProfile in refresh is rejected by conforming servers.
        NSString *boundID=[[bound stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
        if (![boundID isEqual:identifier.lowercaseString]) { callback(PJAuthError(@"Invalid Minecraft profile."),NO); return; }
        self.authData[@"profileId"]=profile[@"id"]; self.authData[@"username"]=profile[@"name"]; self.authData[@"accountType"]=@"yggdrasil";
        [YggdrasilAuthenticator ensureAgent:^(NSError *error) { if (error) callback(error,NO); else callback(nil,[self saveChanges]); }];
        return;
    }
    NSDictionary *body=@{@"accessToken":self.authData[@"accessToken"] ?: @"",@"clientToken":self.authData[@"clientToken"] ?: @"",@"selectedProfile":@{@"id":profile[@"id"],@"name":profile[@"name"]},@"requestUser":@YES};
    [YggdrasilAuthenticator request:self.authData[@"authServer"] endpoint:@"authserver/refresh" body:body completion:^(NSDictionary *json,NSError *error) {
        if (error) { callback(error,NO); return; }
        if (![json[@"accessToken"] isKindOfClass:NSString.class] || ![json[@"accessToken"] length]) { callback(PJAuthError(@"The authentication server returned an invalid response."),NO); return; }
        self.authData[@"accessToken"]=json[@"accessToken"]; self.authData[@"clientToken"]=json[@"clientToken"] ?: body[@"clientToken"];
        NSDictionary *selected=[json[@"selectedProfile"] isKindOfClass:NSDictionary.class] ? json[@"selectedProfile"]:profile;
        if (![selected[@"name"] isKindOfClass:NSString.class] || ![selected[@"id"] isKindOfClass:NSString.class]) { callback(PJAuthError(@"Invalid Minecraft profile."),NO); return; }
        self.authData[@"profileId"]=selected[@"id"]; self.authData[@"username"]=selected[@"name"]; self.authData[@"accountType"]=@"yggdrasil";
        [YggdrasilAuthenticator ensureAgent:^(NSError *error) { if (error) callback(error,NO); else callback(nil,[self saveChanges]); }];
    }];
}
- (void)refreshTokenWithCallback:(Callback)callback {
    NSDictionary *tokens=[YggdrasilAuthenticator tokenDataOfProfile:self.authData[@"xuid"]];
    if (![tokens[@"accessToken"] length]) { callback(PJAuthError(localize(@"登录已失效，请重新登录第三方账户。",nil)),NO); return; }
    [YggdrasilAuthenticator request:self.authData[@"authServer"] endpoint:@"authserver/refresh" body:@{@"accessToken":tokens[@"accessToken"],@"clientToken":tokens[@"clientToken"] ?: @"",@"requestUser":@YES} completion:^(NSDictionary *json,NSError *error) {
        if (error) {
            // A transport failure must not destroy a still-cached single-player
            // identity. An authentication rejection must not be treated as success.
            if ([error.domain isEqual:NSURLErrorDomain] && [NSFileManager.defaultManager fileExistsAtPath:YggdrasilAuthenticator.agentPath]) { callback(nil,YES); return; }
            callback(error,NO); return;
        }
        if (![json[@"accessToken"] isKindOfClass:NSString.class] || ![json[@"accessToken"] length]) { callback(PJAuthError(@"The authentication server returned an invalid response."),NO); return; }
        self.authData[@"accessToken"]=json[@"accessToken"]; self.authData[@"clientToken"]=[json[@"clientToken"] isKindOfClass:NSString.class] ? json[@"clientToken"]:tokens[@"clientToken"];
        NSDictionary *selected=[json[@"selectedProfile"] isKindOfClass:NSDictionary.class] ? json[@"selectedProfile"]:nil;
        if ([selected[@"name"] isKindOfClass:NSString.class] && [selected[@"id"] isEqual:self.authData[@"profileId"]]) self.authData[@"username"]=selected[@"name"];
        [YggdrasilAuthenticator ensureAgent:^(NSError *error) { callback(error,error ? NO:[self saveChanges]); }];
    }];
}
@end
