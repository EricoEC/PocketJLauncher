#import <Foundation/Foundation.h>
#import "CurseForgeAPI.h"
#import "AFNetworking.h"
#import "PocketJAddonService.h"
#import "PocketJArchiveService.h"
#import "MinecraftResourceDownloadTask.h"
#import "PLProfiles.h"
#import "utils.h"
#import "ios_uikit_bridge.h"
#if __has_include("CurseForgeSecrets.local.h")
#import "CurseForgeSecrets.local.h"
#else
#import "CurseForgeSecrets.sample.h"
#endif

@implementation CurseForgeAPI
- (instancetype)init { return [super initWithURL:@"https://api.curseforge.com/v1"]; }
- (id)requestEndpoint:(NSString *)endpoint method:(NSString *)method body:(NSDictionary *)body params:(NSDictionary *)params {
    if (NSThread.isMainThread || !POCKETJ_CURSEFORGE_API_KEY.length) {
        self.lastError=[NSError errorWithDomain:@"PocketJ.CurseForge" code:1 userInfo:@{NSLocalizedDescriptionKey:@"CurseForge API key required; requests must run off the main thread."}]; return nil;
    }
    NSURLComponents *parts=[NSURLComponents componentsWithString:[self.baseURL stringByAppendingPathComponent:endpoint]];
    NSMutableArray *query=[NSMutableArray array]; for (NSString *key in params) [query addObject:[NSURLQueryItem queryItemWithName:key value:[params[key] description]]]; parts.queryItems=query;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:parts.URL]; request.HTTPMethod=method; request.timeoutInterval=20;
    [request setValue:POCKETJ_CURSEFORGE_API_KEY forHTTPHeaderField:@"x-api-key"]; [request setValue:@"PocketJLauncher/1.5 (modpacks)" forHTTPHeaderField:@"User-Agent"];
    if (body) { request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; }
    __block id result; __block NSError *failure; dispatch_semaphore_t done=dispatch_semaphore_create(0);
    NSURLSessionDataTask *task=[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        if (data) result=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        NSInteger status=[(NSHTTPURLResponse *)response statusCode];
        failure=error ?: ((status<200 || status>=300) ? [NSError errorWithDomain:@"PocketJ.CurseForge" code:status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"CurseForge HTTP %ld",(long)status]}]:nil);
        dispatch_semaphore_signal(done);
    }]; [task resume];
    if (dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC))) { [task cancel]; failure=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]; }
    self.lastError=failure; return failure ? nil:result;
}
- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params { return [self requestEndpoint:endpoint method:@"GET" body:nil params:params]; }
- (NSMutableArray *)searchModWithFilters:(NSDictionary *)filters previousPageResult:(NSMutableArray *)previous {
    NSMutableDictionary *params=[@{@"gameId":@432,@"classId":@4471,@"pageSize":@50,@"index":@(previous.count),@"searchFilter":filters[@"name"] ?: @"",@"sortField":@2,@"sortOrder":@"desc"} mutableCopy];
    if ([filters[@"mcVersion"] length]) params[@"gameVersion"]=filters[@"mcVersion"];
    NSDictionary *root=[self getEndpoint:@"mods/search" params:params]; if (!root) return nil;
    NSMutableArray *results=previous.mutableCopy ?: [NSMutableArray array];
    for (NSDictionary *item in root[@"data"]) [results addObject:[@{@"apiSource":@2,@"isModpack":@YES,@"id":[item[@"id"] description],@"title":item[@"name"] ?: @"",@"description":item[@"summary"] ?: @"",@"imageUrl":item[@"logo"][@"thumbnailUrl"] ?: @""} mutableCopy]];
    self.reachedLastPage=results.count >= [root[@"pagination"][@"totalCount"] unsignedIntegerValue]; return results;
}
- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    PocketJAddonService *service=[[PocketJAddonService alloc] initWithCurseForgeKey:POCKETJ_CURSEFORGE_API_KEY];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [service versionsForProvider:@"CurseForge" project:item[@"id"] minecraft:@"" loader:@"" compatibleOnly:NO completion:^(NSArray *versions,NSError *error) {
        self.lastError=error;
        NSMutableArray *names=[NSMutableArray array], *games=[NSMutableArray array], *urls=[NSMutableArray array], *hashes=[NSMutableArray array], *sizes=[NSMutableArray array], *fileIDs=[NSMutableArray array];
        for (NSDictionary *version in versions) {
            NSDictionary *file=version[@"payload"]; NSString *url=file[@"url"];
            // An unavailable distribution URL is resolved on selection below.
            if (!url.length) url=[NSString stringWithFormat:@"curseforge://%@/%@",item[@"id"],file[@"cfFileID"]];
            NSString *mc=@""; for (NSString *candidate in version[@"gameVersions"]) if ([candidate rangeOfString:@"^[0-9]+\\.[0-9]" options:NSRegularExpressionSearch].location!=NSNotFound) { mc=candidate; break; }
            [names addObject:version[@"title"]]; [games addObject:mc]; [urls addObject:url]; [hashes addObject:file[@"hashes"][@"sha1"] ?: @""]; [sizes addObject:file[@"size"] ?: @0]; [fileIDs addObject:file[@"cfFileID"] ?: @""];
        }
        item[@"versionNames"]=names; item[@"mcVersionNames"]=games; item[@"versionUrls"]=urls; item[@"versionHashes"]=hashes; item[@"versionSizes"]=sizes; item[@"versionFileIDs"]=fileIDs; item[@"versionDetailsLoaded"]=@(!error);
        dispatch_semaphore_signal(done);
    }];
    // Caller is the existing modpack browser's worker queue, never the UI.
    if (dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_SEC))) self.lastError=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
}
- (void)installModpackFromDetail:(NSDictionary *)detail atIndex:(NSUInteger)index {
    NSString *url=detail[@"versionUrls"][index];
    if (![url hasPrefix:@"curseforge://"]) { [super installModpackFromDetail:detail atIndex:index]; return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSString *fileID=detail[@"versionFileIDs"][index];
        NSDictionary *root=[self getEndpoint:[NSString stringWithFormat:@"mods/%@/files/%@/download-url",detail[@"id"],fileID] params:nil];
        NSString *download=[root[@"data"] isKindOfClass:NSString.class] ? root[@"data"]:nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!download.length) { showDialog(localize(@"下载失败",nil),self.lastError.localizedDescription ?: localize(@"该作者不允许第三方下载，请从项目页面手动获取。",nil)); return; }
            NSMutableDictionary *resolved=detail.mutableCopy; NSMutableArray *urls=[detail[@"versionUrls"] mutableCopy]; urls[index]=download; resolved[@"versionUrls"]=urls;
            [super installModpackFromDetail:resolved atIndex:index];
        });
    });
}
- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)package toPath:(NSString *)path {
    NSError *error=nil;
    if (![PocketJArchiveService validateArchive:package error:&error]) { [downloader finishDownloadWithErrorString:error.localizedDescription]; return; }
    UZKArchive *archive=[[UZKArchive alloc] initWithPath:package error:&error];
    NSData *data=[archive extractDataFromFile:self.archiveRootPrefix.length ? [self.archiveRootPrefix stringByAppendingPathComponent:@"manifest.json"]:@"manifest.json" error:&error];
    NSDictionary *manifest=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error]:nil;
    if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"minecraft"][@"version"] length]) { [downloader finishDownloadWithErrorString:error.localizedDescription ?: @"Invalid CurseForge manifest.json"]; return; }
    NSMutableArray *IDs=[NSMutableArray array]; for (NSDictionary *entry in manifest[@"files"]) if ([entry[@"required"] boolValue] && entry[@"fileID"]) [IDs addObject:entry[@"fileID"]];
    NSMutableDictionary *filesByID=[NSMutableDictionary dictionary];
    for (NSUInteger offset=0;offset<IDs.count;offset+=50) {
        NSArray *batch=[IDs subarrayWithRange:NSMakeRange(offset,MIN((NSUInteger)50,IDs.count-offset))];
        NSDictionary *root=[self requestEndpoint:@"mods/files" method:@"POST" body:@{@"fileIds":batch} params:nil];
        if (!root) { [downloader finishDownloadWithErrorString:self.lastError.localizedDescription]; return; }
        for (NSDictionary *file in root[@"data"]) filesByID[[file[@"id"] description]]=file;
    }
    for (NSDictionary *entry in manifest[@"files"]) {
        if (![entry[@"required"] boolValue]) continue;
        NSDictionary *file=filesByID[[entry[@"fileID"] description]]; NSString *url=[file[@"downloadUrl"] isKindOfClass:NSString.class] ? file[@"downloadUrl"]:nil;
        if (!url.length) {
            NSDictionary *root=[self getEndpoint:[NSString stringWithFormat:@"mods/%@/files/%@/download-url",entry[@"projectID"],entry[@"fileID"]] params:nil];
            url=[root[@"data"] isKindOfClass:NSString.class] ? root[@"data"]:nil;
        }
        NSString *filename=file[@"fileName"];
        if (!url.length || !filename.length || ![filename isEqual:filename.lastPathComponent]) { [downloader finishDownloadWithErrorString:@"A CurseForge file is unavailable for third-party distribution. Install it manually from its project page."]; return; }
        NSString *sha=nil; for (NSDictionary *hash in file[@"hashes"]) if ([hash[@"algo"] integerValue]==1) sha=hash[@"value"];
        NSURLSessionDownloadTask *task=[downloader createDownloadTask:url size:[file[@"fileLength"] unsignedIntegerValue] sha:sha altName:nil toPath:[[path stringByAppendingPathComponent:@"mods"] stringByAppendingPathComponent:filename]];
        [task resume]; if (downloader.progress.cancelled) return;
    }
    NSString *overrides=manifest[@"overrides"] ?: @"overrides";
    if (![overrides isKindOfClass:NSString.class] || [overrides containsString:@".."] || [overrides hasPrefix:@"/"]) { [downloader finishDownloadWithErrorString:@"Invalid overrides path."]; return; }
    if (self.archiveRootPrefix.length) overrides=[self.archiveRootPrefix stringByAppendingPathComponent:overrides];
    [ModpackUtils archive:archive extractDirectory:overrides toPath:path error:&error];
    if (error) { [downloader finishDownloadWithErrorString:error.localizedDescription]; return; }
    NSMutableDictionary *profile=PLProfiles.current.selectedProfile; NSString *mc=manifest[@"minecraft"][@"version"];
    profile[@"lastVersionId"]=mc; profile[@"pocketjMinecraftVersion"]=mc; profile[@"pocketjLoader"]=@"vanilla";
    for (NSDictionary *loader in manifest[@"minecraft"][@"modLoaders"]) {
        if (![loader[@"primary"] boolValue]) continue;
        NSString *identifier=loader[@"id"];
        for (NSString *kind in @[@"neoforge",@"forge",@"fabric",@"quilt"]) {
            NSString *prefix=[kind stringByAppendingString:@"-"];
            if ([identifier hasPrefix:prefix]) { profile[@"pocketjLoader"]=kind; profile[@"pocketjLoaderVersion"]=[identifier substringFromIndex:prefix.length]; profile[@"pocketjLoaderInstallPending"]=@YES; break; }
        }
    }
    [profile removeObjectForKey:@"pocketjPendingModpack"]; profile[@"pocketjResourcesVerified"]=@NO; [PLProfiles.current save];
}
@end
