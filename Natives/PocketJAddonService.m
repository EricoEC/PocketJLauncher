#import "PocketJAddonService.h"
#import "PocketJModStore.h"
static NSError *PJAPIError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"PocketJ.Catalog" code:code userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(message,nil)}];
}
static NSString *PJString(id value) { return [value isKindOfClass:NSString.class] ? value:nil; }
static NSArray *PJArray(id value) { return [value isKindOfClass:NSArray.class] ? value:@[]; }
@interface PocketJAddonService ()
@property(nonatomic) NSString *key;
@property(nonatomic) NSOperationQueue *queue;
@end
@implementation PocketJAddonService
- (instancetype)initWithCurseForgeKey:(NSString *)key {
    if ((self=[super init])) { _key = key ?: @""; _queue = [NSOperationQueue new]; _queue.maxConcurrentOperationCount = 3; _queue.qualityOfService = NSQualityOfServiceUtility; }
    return self;
}
// Only called on the bounded worker queue, never on the UI thread. No nested
// queue dispatch; each request owns its state instead of global singleton fields.
- (id)JSON:(NSString *)url method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.timeoutInterval = 20; request.HTTPMethod = method ?: @"GET";
    [request setValue:@"PocketJLauncher/1.5 (Erico; catalog)" forHTTPHeaderField:@"User-Agent"];
    if ([request.URL.host isEqual:@"api.curseforge.com"]) {
        if (!self.key.length) { if (error) *error = PJAPIError(401, @"A CurseForge API key is required."); return nil; }
        [request setValue:self.key forHTTPHeaderField:@"x-api-key"];
    }
    if (body) { request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:error]; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; }
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block NSData *data; __block NSError *failure; __block NSInteger status;
    NSURLSessionDataTask *task=[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *response, NSURLResponse *http, NSError *e) { data=response; failure=e; status=[(NSHTTPURLResponse *)http statusCode]; dispatch_semaphore_signal(done); }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 25*NSEC_PER_SEC))) { [task cancel]; if (error) *error=PJAPIError(NSURLErrorTimedOut,@"The catalog request timed out."); return nil; }
    if (failure || status<200 || status>=300) { if (error) *error=failure ?: PJAPIError(status,[NSString stringWithFormat:NSLocalizedString(@"Catalog returned HTTP %ld.",nil),(long)status]); return nil; }
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
}
- (NSArray *)versions:(NSString *)provider project:(NSString *)project minecraft:(NSString *)mc loader:(NSString *)loader compatible:(BOOL)only error:(NSError **)error {
    if (!project.length || [project rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet]].location != NSNotFound) {
        if (error) *error=PJAPIError(400,@"Invalid project identifier."); return nil;
    }
    BOOL cf=[provider isEqual:@"CurseForge"];
    NSMutableArray *raw=[NSMutableArray array];
    if (cf) {
        // CurseForge's files endpoint is paginated. Never silently stop at the
        // first 50 files; keep full history, with an explicit safety-limit error.
        for (NSUInteger page=0;page<100;page++) {
            NSString *url=[NSString stringWithFormat:@"https://api.curseforge.com/v1/mods/%@/files?pageSize=50&index=%lu",project,(unsigned long)(page*50)];
            if (only && mc.length) {
                NSURLComponents *parts=[NSURLComponents componentsWithString:url];
                NSMutableArray *query=[parts.queryItems mutableCopy];
                [query addObject:[NSURLQueryItem queryItemWithName:@"gameVersion" value:mc]];
                NSNumber *type=@{@"forge":@1,@"fabric":@4,@"quilt":@5,@"neoforge":@6}[loader];
                if (type) [query addObject:[NSURLQueryItem queryItemWithName:@"modLoaderType" value:type.stringValue]];
                parts.queryItems=query; url=parts.URL.absoluteString;
            }
            id root=[self JSON:url method:nil body:nil error:error]; if (!root) return nil;
            NSArray *files=[root isKindOfClass:NSDictionary.class] && [root[@"data"] isKindOfClass:NSArray.class] ? root[@"data"] : nil;
            if (!files) { if (error) *error=PJAPIError(422,@"Malformed CurseForge version list."); return nil; }
            [raw addObjectsFromArray:files];
            NSUInteger total=[root[@"pagination"][@"totalCount"] unsignedIntegerValue];
            if (files.count<50 || (total && raw.count>=total)) break;
            if (page==99) { if (error) *error=PJAPIError(413,@"This project has too many versions. Narrow the Minecraft version filter."); return nil; }
        }
    } else {
        id result=[self JSON:[NSString stringWithFormat:@"https://api.modrinth.com/v2/project/%@/version?include_changelog=false",project] method:nil body:nil error:error];
        if (![result isKindOfClass:NSArray.class]) { if (error && !*error) *error=PJAPIError(422,@"Malformed Modrinth version list."); return nil; } [raw addObjectsFromArray:result];
    }
    NSMutableArray *versions=[NSMutableArray array];
    for (NSDictionary *version in raw) {
        if (![version isKindOfClass:NSDictionary.class]) continue;
        NSArray *games=PJArray(version[cf ? @"gameVersions":@"game_versions"]);
        NSArray *loaders=PJArray(version[@"loaders"]);
        BOOL loaderOK=!loader.length || [loader isEqual:@"vanilla"];
        for (NSString *candidate in (cf ? games:loaders)) if ([candidate isKindOfClass:NSString.class] && [candidate.lowercaseString isEqual:loader.lowercaseString]) loaderOK=YES;
        BOOL compatible=(!mc.length || [games containsObject:mc]) && loaderOK;
        if (only && !compatible) continue;
        NSDictionary *file=version;
        if (!cf) {
            file=nil;
            for (NSDictionary *candidate in PJArray(version[@"files"])) if ([candidate isKindOfClass:NSDictionary.class] && [candidate[@"primary"] boolValue]) { file=candidate; break; }
            file=file ?: [PJArray(version[@"files"]) firstObject];
        }
        if (![file isKindOfClass:NSDictionary.class]) continue;
        NSString *url=PJString(file[cf ? @"downloadUrl":@"url"]);
        // Missing CF URLs are resolved via the official endpoint on selection,
        // not guessed from CDN paths or bypassed when distribution is disabled.
        NSString *name=PJString(file[cf ? @"fileName":@"filename"]);
        if (!name.length) continue;
        NSMutableDictionary *hashes=(!cf && [file[@"hashes"] isKindOfClass:NSDictionary.class]) ? [file[@"hashes"] mutableCopy]:[NSMutableDictionary dictionary];
        if (cf) for (NSDictionary *hash in PJArray(file[@"hashes"])) if ([hash isKindOfClass:NSDictionary.class] && [hash[@"algo"] integerValue]==1 && [hash[@"value"] isKindOfClass:NSString.class]) hashes[@"sha1"]=hash[@"value"];
        NSString *versionID=[version[@"id"] description];
        NSMutableDictionary *metadata=[@{@"provider":provider, @"projectID":project, @"versionID":versionID ?: @"", @"dependencies":PJArray(version[@"dependencies"])} mutableCopy];
        NSMutableDictionary *payload=[@{@"filename":name, @"hashes":hashes ?: @{}, @"archive":@YES, @"pjMetadata":metadata} mutableCopy];
        if (url.length) payload[@"url"]=url;
        if (cf) payload[@"cfFileID"]=versionID;
        if (file[cf ? @"fileLength":@"size"]) payload[@"size"]=file[cf ? @"fileLength":@"size"];
        NSString *title=PJString(version[cf ? @"displayName":@"name"]) ?: name;
        NSString *release=cf ? (@{@1:@"release",@2:@"beta",@3:@"alpha"}[version[@"releaseType"]] ?: @"") : (version[@"version_type"] ?: @"");
        NSString *subtitle=[NSString stringWithFormat:@"%@ · %@",release,[games componentsJoinedByString:@", "]];
        [versions addObject:@{@"title":title, @"subtitle":subtitle, @"gameVersions":games, @"compatible":@(compatible), @"payload":payload, @"date":version[cf ? @"fileDate":@"date_published"] ?: @""}];
    }
    [versions sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [b[@"date"] compare:a[@"date"]]; }];
    return versions;
}
- (void)versionsForProvider:(NSString *)provider project:(NSString *)project minecraft:(NSString *)mc loader:(NSString *)loader compatibleOnly:(BOOL)compatible completion:(PJAddonVersions)completion {
    [self.queue addOperationWithBlock:^{ NSError *error=nil; NSArray *versions=[self versions:provider project:project minecraft:mc loader:loader compatible:compatible error:&error]; dispatch_async(dispatch_get_main_queue(), ^{ completion(versions,error); }); }];
}
+ (uint32_t)curseForgeFingerprint:(NSData *)data {
    const uint8_t *bytes=data.bytes; NSUInteger length=data.length, filtered=0;
    for (NSUInteger i=0;i<length;i++) if (bytes[i]!=9 && bytes[i]!=10 && bytes[i]!=13 && bytes[i]!=32) filtered++;
    const uint32_t m=0x5bd1e995; uint32_t h=1 ^ (uint32_t)filtered, k=0; NSUInteger pending=0;
    for (NSUInteger i=0;i<length;i++) {
        uint8_t b=bytes[i]; if (b==9||b==10||b==13||b==32) continue;
        k |= (uint32_t)b << (8*pending++);
        if (pending==4) { k*=m; k^=k>>24; k*=m; h*=m; h^=k; k=0; pending=0; }
    }
    if (pending) { h^=k; h*=m; } h^=h>>13; h*=m; h^=h>>15; return h;
}
- (void)resolveDownload:(NSDictionary *)file completion:(void (^)(NSDictionary *, NSError *))completion {
    if ([file[@"url"] length]) { completion(file,nil); return; }
    NSDictionary *metadata=file[@"pjMetadata"];
    if (![metadata[@"provider"] isEqual:@"CurseForge"] || !file[@"cfFileID"]) { completion(nil,PJAPIError(404,@"No download URL is available for this file.")); return; }
    [self.queue addOperationWithBlock:^{
        NSError *error=nil;
        NSString *url=[NSString stringWithFormat:@"https://api.curseforge.com/v1/mods/%@/files/%@/download-url",metadata[@"projectID"],file[@"cfFileID"]];
        id root=[self JSON:url method:nil body:nil error:&error];
        NSString *download=[root[@"data"] isKindOfClass:NSString.class] ? root[@"data"] : nil;
        NSMutableDictionary *resolved=download.length ? file.mutableCopy:nil; resolved[@"url"]=download;
        if (!resolved && !error) error=PJAPIError(403,@"The author has not provided a third-party download URL.");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(resolved,error); });
    }];
}
- (void)identifyFile:(NSString *)path record:(NSDictionary *)record completion:(void (^)(NSDictionary *, NSError *))completion {
    if ([record[@"provider"] length] && [record[@"projectID"] length]) { completion(record,nil); return; }
    [self.queue addOperationWithBlock:^{
        NSError *error=nil; NSDictionary *identity=nil;
        NSString *hash=record[@"sha1"] ?: [PocketJModStore sha1AtPath:path];
        id version=hash ? [self JSON:[NSString stringWithFormat:@"https://api.modrinth.com/v2/version_file/%@?algorithm=sha1",hash] method:nil body:nil error:&error] : nil;
        if ([version isKindOfClass:NSDictionary.class] && [version[@"project_id"] length]) identity=@{@"provider":@"Modrinth",@"projectID":version[@"project_id"],@"versionID":version[@"id"] ?: @""};
        if (!identity && self.key.length) {
            NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
            if (data) {
                uint32_t fingerprint=[PocketJAddonService curseForgeFingerprint:data];
                id root=[self JSON:@"https://api.curseforge.com/v1/fingerprints/432" method:@"POST" body:@{@"fingerprints":@[@(fingerprint)]} error:&error];
                NSDictionary *match=[root[@"data"][@"exactMatches"] firstObject];
                if (match[@"id"]) identity=@{@"provider":@"CurseForge",@"projectID":[match[@"id"] description],@"versionID":[match[@"file"][@"id"] description] ?: @""};
            }
        }
        if (identity) error=nil;
        else if (!error || error.code==404) error=PJAPIError(404,@"This file is not identified by Modrinth or CurseForge. Link a project before choosing a version.");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(identity,error); });
    }];
}
- (BOOL)visitFile:(NSDictionary *)file optional:(BOOL)optional depth:(NSUInteger)depth
       installed:(NSArray *)installed minecraft:(NSString *)mc loader:(NSString *)loader
         visited:(NSMutableDictionary *)visited output:(NSMutableArray *)output error:(NSError **)error {
    if (depth>12 || visited.count>=64) { if (error) *error=PJAPIError(413,@"Dependency graph exceeds the safety limit (64 projects / 12 levels)."); return NO; }
    NSDictionary *meta=file[@"pjMetadata"]; NSString *provider=meta[@"provider"], *project=meta[@"projectID"], *version=meta[@"versionID"];
    NSString *key=[NSString stringWithFormat:@"%@:%@",provider,project];
    NSDictionary *prior=visited[key];
    if (prior) {
        if (![prior[@"pjMetadata"][@"versionID"] isEqual:version]) { if (error) *error=PJAPIError(409,@"Dependencies require conflicting versions of the same project."); return NO; }
        // Required paths dominate optional paths. Preserve shared dependencies
        // in a diamond graph rather than relying on a global visited singleton.
        if (!optional && [prior[@"pjOptional"] boolValue]) {
            [visited removeObjectForKey:key]; [output removeObject:prior];
            // Revisit this subtree so required grandchildren are promoted too.
        } else return YES;
    }
    NSMutableDictionary *planned=file.mutableCopy; planned[@"pjOptional"]=@(optional); visited[key]=planned;
    BOOL alreadyInstalled=NO;
    for (NSDictionary *existing in installed) {
        if ([existing[@"provider"] isEqual:provider] && [existing[@"projectID"] isEqual:project]) {
            if ([existing[@"versionID"] isEqual:version] && [existing[@"enabled"] boolValue]) { alreadyInstalled=YES; continue; }
            if ([existing[@"updateLocked"] boolValue]) { if (error) *error=PJAPIError(409,@"A required dependency is locked. Unlock it before changing versions."); return NO; }
            planned[@"pjReplacingFile"]=existing[@"fileName"];
            planned[@"pjEnableAfterInstall"]=@YES;
        }
    }
    for (NSDictionary *edge in meta[@"dependencies"] ?: @[]) {
        if (![edge isKindOfClass:NSDictionary.class]) continue;
        BOOL cf=[provider isEqual:@"CurseForge"];
        BOOL required=cf ? [edge[@"relationType"] integerValue]==3 : [edge[@"dependency_type"] isEqual:@"required"];
        BOOL recommended=cf ? [edge[@"relationType"] integerValue]==2 : [edge[@"dependency_type"] isEqual:@"optional"];
        if (!required && !recommended) continue;
        NSString *dependencyProject=cf ? [edge[@"modId"] description] : edge[@"project_id"];
        NSString *dependencyVersion=cf ? nil : edge[@"version_id"];
        if (![dependencyProject isKindOfClass:NSString.class]) dependencyProject=nil;
        if (![dependencyVersion isKindOfClass:NSString.class]) dependencyVersion=nil;
        if (!dependencyProject.length && dependencyVersion.length) {
            id raw=[self JSON:[NSString stringWithFormat:@"https://api.modrinth.com/v2/version/%@",dependencyVersion] method:nil body:nil error:error];
            dependencyProject=[raw[@"project_id"] isKindOfClass:NSString.class] ? raw[@"project_id"]:nil;
        }
        if (!dependencyProject.length) {
            if (required) { if (error) *error=PJAPIError(422,@"A required dependency has no resolvable project identifier."); return NO; }
            continue;
        }
        NSError *dependencyError=nil;
        NSArray *versions=[self versions:provider project:dependencyProject minecraft:mc loader:loader compatible:YES error:&dependencyError];
        NSDictionary *selected=nil;
        for (NSDictionary *candidate in versions) {
            if (!dependencyVersion.length || [candidate[@"payload"][@"pjMetadata"][@"versionID"] isEqual:dependencyVersion]) { selected=candidate[@"payload"]; break; }
        }
        if (!selected) {
            if (required) { if (error) *error=dependencyError ?: PJAPIError(404,@"No compatible version of a required dependency is available."); return NO; }
            continue;
        }
        if (![self visitFile:selected optional:(optional || !required) depth:depth+1 installed:installed minecraft:mc loader:loader visited:visited output:output error:error]) return NO;
    }
    if (!alreadyInstalled) [output addObject:planned]; // still inspect installed dependency closures
    return YES;
}
- (void)dependencyPlanForFile:(NSDictionary *)file installed:(NSArray *)installed minecraft:(NSString *)minecraft loader:(NSString *)loader completion:(PJAddonVersions)completion {
    [self.queue addOperationWithBlock:^{
        NSError *error=nil; NSMutableArray *plan=[NSMutableArray array];
        [self visitFile:file optional:NO depth:0 installed:installed minecraft:minecraft loader:loader visited:[NSMutableDictionary dictionary] output:plan error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error ? nil:plan,error); });
    }];
}
@end
