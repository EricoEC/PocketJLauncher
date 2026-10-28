#include "PocketJEnvironment.h"
#import <Foundation/Foundation.h>
#import "PocketJModStore.h"
#import "PocketJDownloadClient.h"
#import "PocketJAddonService.h"
#import "PocketJModSearchIndex.h"
#import "PocketJCrashDiagnostics.h"
#import "PocketJInstanceContext.h"
#import "authenticator/PocketJAccountIdentity.h"

static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@",message); exit(1); }
}
@interface PocketJModStore (TestHooks)
- (BOOL)saveCatalog:(NSDictionary *)catalog error:(NSError **)error;
@end
@interface PJFailingStore : PocketJModStore @end
@implementation PJFailingStore
- (BOOL)saveCatalog:(NSDictionary *)catalog error:(NSError **)error { if (error) *error=[NSError errorWithDomain:@"TestDiskFull" code:1 userInfo:nil]; return NO; }
@end
@interface PJMockCatalog : NSURLProtocol @end
@implementation PJMockCatalog
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host hasSuffix:@"modrinth.com"] || [request.URL.host isEqual:@"api.curseforge.com"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSString *path=self.request.URL.path; id object;
    if ([path hasPrefix:@"/v2/project/"]) {
        object=@[@{@"id":@"v2",@"project_id":@"test",@"name":@"Release",@"version_type":@"release",@"date_published":@"2026-10-28",@"game_versions":@[@"1.21.11"],@"loaders":@[@"fabric"],@"dependencies":@[],@"files":@[@{@"url":@"https://example.com/mod.jar",@"filename":@"mod.jar",@"primary":@YES,@"hashes":@{}}]},
            @{@"id":@"v1",@"name":@"Old",@"date_published":@"2025-01-01",@"game_versions":@[@"1.20.1"],@"loaders":@[@"forge"],@"files":@[@{@"url":@"https://example.com/old.jar",@"filename":@"old.jar"}]}];
    } else {
        BOOL last=[self.request.URL.query containsString:@"index=50"];
        NSMutableArray *files=[NSMutableArray array];
        for (NSUInteger i=0;i<(last ? 1:50);i++) [files addObject:@{@"id":@(i+(last ? 50:0)),@"modId":@123,@"fileName":[NSString stringWithFormat:@"mod-%lu.jar",(unsigned long)i],@"displayName":@"Test",@"gameVersions":@[@"1.21.11",@"Fabric"],@"releaseType":@1,@"fileDate":@"2026-10-28",@"dependencies":@[],@"hashes":@[]}];
        object=@{@"data":files,@"pagination":@{@"totalCount":@51}};
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

int main(void) { @autoreleasepool {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *fm=NSFileManager.defaultManager;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    PocketJSetEnv("POCKETJ_HOME",root.UTF8String,1);
    PocketJModStore *store=[[PocketJModStore alloc] initWithInstancePath:[root stringByAppendingPathComponent:@"instance"]];
    NSString *identity=store.instanceID;
    Check([[[PocketJModStore alloc] initWithInstancePath:store.instancePath].instanceID isEqual:identity],@"instance UUID stable across relaunch");
    Check(![PocketJModStore isSafeFileName:@"../escape.jar"] && ![PocketJModStore isSafeFileName:@"a\\b.jar"],@"path traversal rejected");
    NSURL *source=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"input.jar"]];
    const unsigned char bytes[]={0x50,0x4b,0x03,0x04,1,2,3,4};
    NSData *data=[NSData dataWithBytes:bytes length:sizeof(bytes)]; [data writeToURL:source atomically:YES];
    NSError *error=nil;
    Check([store installJar:source fileName:@"test.jar" replacingFile:nil metadata:@{@"dependencies":@[@{@"project_id":NSNull.null}]} error:&error],@"install safely sanitizes JSON null metadata");
    NSArray *mods=[store scan:&error]; Check(mods.count==1 && !error,@"scan finds JAR");
    NSString *modID=mods.firstObject[@"id"];
    Check([store annotateFile:@"test.jar" values:@{@"alias":@"钠优化",@"notes":@"性能 中文搜索"} error:&error],@"annotations saved");
    Check([PocketJModStore filterMods:[store scan:&error] query:@"中文 性能"].count==1,@"Chinese multiword local search");
    Check([store setEnabled:NO file:@"test.jar" error:&error],@"disable using suffix");
    Check([store installJar:source fileName:@"updated.jar" replacingFile:@"test.jar.disabled" metadata:@{} error:&error],@"replace disabled mod");
    mods=[store scan:&error]; Check(mods.count==1 && ![mods.firstObject[@"enabled"] boolValue] && [mods.firstObject[@"id"] isEqual:modID],@"replacement preserves identity and disabled state");
    NSString *installed=[store.modsPath stringByAppendingPathComponent:@"updated.jar.disabled"];
    Check([fm fileExistsAtPath:installed] && ![fm fileExistsAtPath:[store.modsPath stringByAppendingPathComponent:@"test.jar.disabled"]],@"old JAR removed only after successful install");
    [@"bad html" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:nil];
    error=nil; Check(![store installJar:source fileName:@"bad.jar" replacingFile:@"updated.jar.disabled" metadata:@{} error:&error] && [fm fileExistsAtPath:installed],@"bad replacement preserves original");
    error=nil; Check(![PocketJDownloadClient verifyFile:source descriptor:@{@"archive":@YES} error:&error],@"HTML archive rejected");
    [data writeToURL:source atomically:YES];
    PJFailingStore *failing=[[PJFailingStore alloc] initWithInstancePath:store.instancePath]; error=nil;
    Check(![failing installJar:source fileName:@"disk-full.jar" replacingFile:@"updated.jar.disabled" metadata:@{} error:&error] && [fm fileExistsAtPath:installed] && ![fm fileExistsAtPath:[store.modsPath stringByAppendingPathComponent:@"disk-full.jar.disabled"]],@"metadata write failure rolls back original JAR");
    [data writeToURL:source atomically:YES]; error=nil;
    Check(![PocketJDownloadClient verifyFile:source descriptor:@{@"hashes":@{@"sha1":@"0000000000000000000000000000000000000000"}} error:&error],@"hash mismatch rejected");
    error=nil; Check([PocketJDownloadClient verifyFile:source descriptor:@{@"archive":@YES,@"size":@(sizeof(bytes))} error:&error],@"size and ZIP signature verified");
    NSString *link=[store.modsPath stringByAppendingPathComponent:@"link.jar"];
    [fm createSymbolicLinkAtPath:link withDestinationPath:source.path error:nil];
    Check([store scan:&error].count==1,@"symlink not scanned or hashed");
    Check([store deleteFiles:@[@"updated.jar.disabled"] error:&error],@"permanent deletion");
    [fm removeItemAtPath:store.instancePath error:nil];
    Check(![[[PocketJModStore alloc] initWithInstancePath:store.instancePath].instanceID isEqual:identity],@"recreated same-name instance gets fresh UUID");
    Check([PocketJAddonService curseForgeFingerprint:[@"a b\nc\r\td" dataUsingEncoding:NSUTF8StringEncoding]] == [PocketJAddonService curseForgeFingerprint:[@"abcd" dataUsingEncoding:NSUTF8StringEncoding]],@"CurseForge fingerprint ignores whitespace");
    [NSURLProtocol registerClass:PJMockCatalog.class];
    PocketJAddonService *service=[[PocketJAddonService alloc] initWithCurseForgeKey:@"test-key-not-a-real-secret"];
    __block NSUInteger callbacks=0;
    [service versionsForProvider:@"Modrinth" project:@"test" minecraft:@"1.21.11" loader:@"fabric" compatibleOnly:YES completion:^(NSArray *versions,NSError *e) { Check(!e && versions.count==1,@"MC/loader filters stay separate"); Check([versions.firstObject[@"payload"][@"pjMetadata"][@"versionID"] isEqual:@"v2"],@"provider version ID retained"); callbacks++; }];
    [service versionsForProvider:@"CurseForge" project:@"123" minecraft:@"1.21.11" loader:@"fabric" compatibleOnly:YES completion:^(NSArray *versions,NSError *e) { Check(!e && versions.count==51,@"CurseForge reads beyond first page"); callbacks++; }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while (callbacks<2 && [deadline timeIntervalSinceNow]>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(callbacks==2,@"catalog completion on main thread");
    __block BOOL dependenciesDone=NO;
    NSDictionary *rootFile=@{@"filename":@"root.jar",@"url":@"https://example.com/root.jar",@"pjMetadata":@{@"provider":@"Modrinth",@"projectID":@"root",@"versionID":@"root-v1",@"dependencies":@[@{@"dependency_type":@"required",@"project_id":@"dep-a"},@{@"dependency_type":@"optional",@"project_id":@"dep-b"}]}};
    [service dependencyPlanForFile:rootFile installed:@[] minecraft:@"1.21.11" loader:@"fabric" completion:^(NSArray *plan,NSError *e) { Check(!e && plan.count==3,@"required and optional dependency plan"); NSUInteger optional=0; for (NSDictionary *entry in plan) if ([entry[@"pjOptional"] boolValue]) optional++; Check(optional==1,@"optional dependencies default off"); Check([plan.lastObject[@"filename"] isEqual:@"root.jar"],@"dependencies installed before root"); dependenciesDone=YES; }];
    deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while (!dependenciesDone && [deadline timeIntervalSinceNow]>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(dependenciesDone,@"dependency completion");
    NSArray *csv=[PocketJModSearchIndex parseCSV:@"aliases,query\n\"钠|钠优化\",Sodium\n\"带逗号,名称\",\"Quoted \"\"Name\"\"\"\n"];
    Check(csv.count==3 && [csv[2][1] isEqual:@"Quoted \"Name\""],@"CSV quoting and Chinese names");
    NSURL *csvURL=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"aliases.csv"]];
    [@"钠|钠优化,Sodium\n" writeToURL:csvURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    error=nil; Check([PocketJModSearchIndex.shared importCSV:csvURL error:&error],@"import extensible offline search index");
    Check([[PocketJModSearchIndex.shared onlineQuery:@"钠优化" installed:@[]] isEqual:@"Sodium"],@"Chinese query resolves via imported index");
    Check([[PocketJModSearchIndex.shared onlineQuery:@"一个未知模组" installed:@[]] isEqual:@"一个未知模组"],@"unknown Chinese query is not replaced by a default");
    Check([[PocketJCrashDiagnostics analyze:@"java.lang.OutOfMemoryError"][@"kind"] isEqual:@"heap"],@"memory diagnosis");
    Check([[PocketJCrashDiagnostics analyze:@"normal shutdown"][@"kind"] isEqual:@"unknown"],@"unknown log stays inconclusive");
    NSDictionary *profile=@{@"selectedProfile":@"test",@"profiles":@{@"test":@{@"lastVersionId":@"fabric-loader-0.18.0-1.21.11"}}};
    [[NSJSONSerialization dataWithJSONObject:profile options:0 error:nil] writeToFile:[store.instancePath stringByAppendingPathComponent:@"launcher_profiles.json"] atomically:YES];
    PocketJInstanceContext *context=[[PocketJInstanceContext alloc] initWithInstancePath:store.instancePath];
    Check([context.minecraftVersion isEqual:@"1.21.11"] && [context.loader isEqual:@"fabric"],@"Fabric Loader version never becomes the Minecraft version");
    NSDictionary *snapshot=@{@"selectedProfile":@"test",@"profiles":@{@"test":@{@"lastVersionId":@"fabric-loader-0.18.0-26.3-snapshot-1"}}};
    [[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil] writeToFile:[store.instancePath stringByAppendingPathComponent:@"launcher_profiles.json"] atomically:YES];
    Check([[[[PocketJInstanceContext alloc] initWithInstancePath:store.instancePath] minecraftVersion] isEqual:@"26.3-snapshot-1"],@"Minecraft snapshot suffix is preserved");
    NSDictionary *local=@{@"username":@"SameName"};
    NSDictionary *microsoft=@{@"username":@"SameName",@"xuid":@"12345"};
    NSDictionary *ygg=@{@"accountType":@"yggdrasil",@"username":@"SameName",@"profileId":@"123456781234123412341234567890ab",@"authServer":@"https://example.com/api/yggdrasil/"};
    NSSet *identities=[NSSet setWithArray:@[[PocketJAccountIdentity storageKey:local],[PocketJAccountIdentity storageKey:microsoft],[PocketJAccountIdentity storageKey:ygg]]];
    Check(identities.count==3,@"same-name local, Microsoft and Yggdrasil identities never collide");
    NSMutableDictionary *other=ygg.mutableCopy; other[@"authServer"]=@"https://another.example/api/yggdrasil/";
    Check(![[PocketJAccountIdentity storageKey:ygg] isEqual:[PocketJAccountIdentity storageKey:other]],@"Yggdrasil identity is scoped to server and UUID");
    Check([[PocketJAccountIdentity normalizedServer:@"HTTPS://EXAMPLE.COM:443/api"] isEqual:@"https://example.com/api/"],@"HTTPS server canonicalization");
    Check(![PocketJAccountIdentity normalizedServer:@"http://example.com/"] && ![PocketJAccountIdentity normalizedServer:@"https://user:pass@example.com/"],@"insecure and credential-bearing server URLs rejected");
    [fm removeItemAtPath:root error:nil];
    NSLog(@"PASS: add-on core filesystem, identity, hash, search and provider pagination tests.");
} return 0; }
