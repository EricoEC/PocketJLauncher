#include <CommonCrypto/CommonDigest.h>

#import "authenticator/BaseAuthenticator.h"
#import "installer/modpack/ModpackAPI.h"
#import "AFNetworking.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "PLProfiles.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface MinecraftResourceDownloadTask ()
@property AFURLSessionManager* manager;
@property(atomic) BOOL terminalFailureDelivered;
@end

@implementation MinecraftResourceDownloadTask

- (instancetype)init {
    self = [super init];
    // TODO: implement background download
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 86400;
    //backgroundSessionConfigurationWithIdentifier:@"net.kdt.pojavlauncher.downloadtask"];
    self.manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    self.fileList = [NSMutableArray new];
    self.progressList = [NSMutableArray new];
    return self;
}

// Add file to the queue
- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path success:(void (^)())success {
    BOOL fileExists = [NSFileManager.defaultManager fileExistsAtPath:path];
    NSString *resumePath = [path stringByAppendingString:@".pocketj.resume"];
    // logSuccess?
    if (fileExists && [self checkSHA:sha forFile:path altName:altName]) {
        [NSFileManager.defaultManager removeItemAtPath:resumePath error:nil];
        NSLog(@"[MCDL] Reusing verified local file %@", altName ?: path.lastPathComponent);
        if (success) success();
        return nil;
    } else if (![self checkAccessWithDialog:YES]) {
        return nil;
    }

    NSString *name = altName ?: path.lastPathComponent;
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    __block NSProgress *progress;
    __block NSURLSessionDownloadTask *task = nil;
    NSURL *(^destination)(NSURL *, NSURLResponse *) = ^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        NSLog(@"[MCDL] Downloading %@", name);
        progress = [self.manager downloadProgressForTask:task];
        if (!size && task) {
            [self addDownloadTaskToProgress:task size:response.expectedContentLength];
            @synchronized (self) {
                [self.fileList addObject:name];
            }
        }
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return [NSURL fileURLWithPath:path];
    };
    void (^completion)(NSURLResponse *, NSURL *, NSError *) =
    ^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        if (error != nil) {
            NSData *resumeData = error.userInfo[@"NSURLSessionDownloadTaskResumeData"];
            if ([resumeData isKindOfClass:NSData.class] && resumeData.length > 0) {
                [NSFileManager.defaultManager createDirectoryAtPath:
                    resumePath.stringByDeletingLastPathComponent
                    withIntermediateDirectories:YES attributes:nil error:nil];
                [resumeData writeToFile:resumePath options:NSDataWritingAtomic error:nil];
                NSLog(@"[MCDL] Saved resume data for %@ (%lu bytes)", name,
                    (unsigned long)resumeData.length);
            } else {
                [NSFileManager.defaultManager removeItemAtPath:resumePath error:nil];
            }
            if (self.progress.cancelled) {
                return;
            }
            [self finishDownloadWithError:error file:name];
        } else if (![self checkSHA:sha forFile:path altName:altName]) {
            [NSFileManager.defaultManager removeItemAtPath:resumePath error:nil];
            [self finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to verify file %@: SHA1 mismatch", path.lastPathComponent]];
        } else {
            [NSFileManager.defaultManager removeItemAtPath:resumePath error:nil];
            progress.totalUnitCount = progress.completedUnitCount;
            if (success) success();
        }
    };

    NSData *resumeData = [NSData dataWithContentsOfFile:resumePath];
    if (resumeData.length > 0) {
        NSLog(@"[MCDL] Resuming interrupted download %@", name);
        task = [self.manager downloadTaskWithResumeData:resumeData
            progress:nil destination:destination completionHandler:completion];
    } else {
        task = [self.manager downloadTaskWithRequest:request
            progress:nil destination:destination completionHandler:completion];
    }

    if (size && task) {
        [self addDownloadTaskToProgress:task size:size];
        @synchronized (self) {
            [self.fileList addObject:name];
        }
    }

    return task;
}

- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path {
    return [self createDownloadTask:url size:size sha:sha altName:altName toPath:path success:nil];
}

- (void)addDownloadTaskToProgress:(NSURLSessionDownloadTask *)task size:(NSInteger)size {
    NSProgress *progress = [self.manager downloadProgressForTask:task];
    NSUInteger fileSize = size>0 ? size : 1;
    progress.kind = NSProgressKindFile;
    if (size > 0) {
        progress.totalUnitCount = fileSize;
    }
    @synchronized (self) {
        [self.progressList addObject:progress];
    }
    [self.progress addChild:progress withPendingUnitCount:fileSize];
    self.progress.totalUnitCount += fileSize;
    self.textProgress.totalUnitCount = self.progress.totalUnitCount;
}

- (void)downloadVersionMetadata:(NSDictionary *)version success:(void (^)())success {
    // Download base json
    NSString *versionStr = version[@"id"];
    if ([versionStr isEqualToString:@"latest-release"]) {
        versionStr = getPrefObject(@"internal.latest_version.release");
    } else if ([versionStr isEqualToString:@"latest-snapshot"]) {
        versionStr = getPrefObject(@"internal.latest_version.snapshot");
    }

    NSString *path = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), versionStr];
    // Find it again to resolve latest-*
    version = (id)[MinecraftResourceUtils findVersion:versionStr inList:remoteVersionList];

    void(^completionBlock)(void) = ^{
        self.metadata = parseJSONFromFile(path);
        if (self.metadata[@"NSErrorObject"]) {
            [self finishDownloadWithErrorString:[self.metadata[@"NSErrorObject"] localizedDescription]];
            return;
        }
        if (self.metadata[@"inheritsFrom"]) {
            NSMutableDictionary *inheritsFromDict = parseJSONFromFile([NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), self.metadata[@"inheritsFrom"]]);
            if (inheritsFromDict) {
                [MinecraftResourceUtils processVersion:self.metadata inheritsFrom:inheritsFromDict];
                self.metadata = inheritsFromDict;
            }
        }
        [MinecraftResourceUtils tweakVersionJson:self.metadata];
        success();
    };

    if (!version) {
        // This is likely local version, check if json exists and has inheritsFrom
        NSMutableDictionary *json = parseJSONFromFile(path);
        if (json[@"NSErrorObject"]) {
            [self finishDownloadWithErrorString:[json[@"NSErrorObject"] localizedDescription]];
            return;
        } else if (json[@"inheritsFrom"]) {
            version = (id)[MinecraftResourceUtils findVersion:json[@"inheritsFrom"] inList:remoteVersionList];
            path = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), json[@"inheritsFrom"]];
            if (!version) {
                // JIT activation intentionally invalidates the global version
                // list. A Forge installer can finish before that list has been
                // fetched again, so resolve its Mojang parent here instead of
                // constructing a request from a nil URL.
                NSString *parentVersion = json[@"inheritsFrom"];
                NSURL *manifestURL = [NSURL URLWithString:
                    @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"];
                [[[NSURLSession sharedSession] dataTaskWithURL:manifestURL
                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    NSDictionary *manifest = data.length
                        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                    NSDictionary *resolved = nil;
                    for (NSDictionary *candidate in manifest[@"versions"] ?: @[]) {
                        if ([candidate[@"id"] isEqualToString:parentVersion]) {
                            resolved = candidate;
                            break;
                        }
                    }
                    if (error || !resolved[@"url"]) {
                        [self finishDownloadWithErrorString:error.localizedDescription ?:
                            [NSString stringWithFormat:localize(@"无法获取 Minecraft %@ 的下载信息。", nil), parentVersion]];
                        return;
                    }
                    NSString *parentPath = [NSString stringWithFormat:
                        @"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), parentVersion];
                    NSString *resolvedURL = resolved[@"url"];
                    NSURLSessionDownloadTask *parentTask = [self createDownloadTask:resolvedURL
                        size:[resolved[@"size"] unsignedLongLongValue]
                        sha:resolvedURL.stringByDeletingLastPathComponent.lastPathComponent
                        altName:nil toPath:parentPath success:completionBlock];
                    [parentTask resume];
                }] resume];
                return;
            }
        } else {
            completionBlock();
            return;
        }
    }

    versionStr = version[@"id"];
    NSString *url = version[@"url"];
    NSString *sha = url.stringByDeletingLastPathComponent.lastPathComponent;
    NSUInteger size = [version[@"size"] unsignedLongLongValue];

    NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:nil toPath:path success:completionBlock];
    [task resume];
}

#pragma mark - Minecraft installation

- (void)downloadAssetMetadataWithSuccess:(void (^)())success {
    NSDictionary *assetIndex = self.metadata[@"assetIndex"];
    if (!assetIndex) {
        success();
        return;
    }
    NSString *name = [NSString stringWithFormat:@"assets/indexes/%@.json", assetIndex[@"id"]];
    NSString *path = [@(getenv("POJAV_GAME_DIR")) stringByAppendingPathComponent:name];
    NSString *url = assetIndex[@"url"];
    NSString *sha = url.stringByDeletingLastPathComponent.lastPathComponent;
    NSUInteger size = [assetIndex[@"size"] unsignedLongLongValue];
    NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:name toPath:path success:^{
        self.metadata[@"assetIndexObj"] = parseJSONFromFile(path);
        success();
    }];
    [task resume];
}

- (NSArray *)downloadClientLibraries {
    NSMutableArray *tasks = [NSMutableArray new];
    for (NSDictionary *library in self.metadata[@"libraries"]) {
        NSString *name = library[@"name"];

        NSMutableDictionary *artifact = [library[@"downloads"][@"artifact"] mutableCopy];
        if ((artifact == nil || ![artifact[@"url"] length]) && [name containsString:@":"]) {
            NSLog(@"[MCDL] Unknown artifact object for %@, attempting to generate one", name);
            artifact = artifact ?: [[NSMutableDictionary alloc] init];
            NSString *prefix = library[@"url"] == nil ? @"https://libraries.minecraft.net/" : [library[@"url"] stringByReplacingOccurrencesOfString:@"http://" withString:@"https://"];
            NSArray *libParts = [name componentsSeparatedByString:@":"];
            if (libParts.count < 3) {
                [self finishDownloadWithErrorString:[NSString stringWithFormat:
                    localize(@"无法解析依赖 %@。", nil), name]];
                return nil;
            }
            NSString *version = [libParts[2] componentsSeparatedByString:@"@"][0];
            NSString *extension = [libParts[2] containsString:@"@"]
                ? [libParts[2] componentsSeparatedByString:@"@"].lastObject : @"jar";
            NSString *classifier = libParts.count > 3 ? libParts[3] : nil;
            NSString *filename = [NSString stringWithFormat:@"%@-%@%@.%@",
                libParts[1], version, classifier.length ? [@"-" stringByAppendingString:classifier] : @"", extension];
            artifact[@"path"] = [NSString stringWithFormat:@"%@/%@/%@/%@",
                [libParts[0] stringByReplacingOccurrencesOfString:@"." withString:@"/"],
                libParts[1], version, filename];
            artifact[@"url"] = [NSString stringWithFormat:@"%@%@", prefix, artifact[@"path"]];
            if (!artifact[@"sha1"] && [library[@"checksums"] count]) {
                artifact[@"sha1"] = library[@"checksums"][0];
            }
        }

        NSString *path = [NSString stringWithFormat:@"%s/libraries/%@", getenv("POJAV_GAME_DIR"), artifact[@"path"]];
        NSString *sha = artifact[@"sha1"];
        NSUInteger size = [artifact[@"size"] unsignedLongLongValue];
        NSString *url = artifact[@"url"];
        if ([library[@"skip"] boolValue]) {
            NSLog(@"[MDCL] Skipped library %@", name);
            continue;
        }

        NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:name toPath:path success:nil];
        if (task) {
            [tasks addObject:task];
        } else if (self.progress.cancelled) {
            return nil;
        }
    }
    return tasks;
}

- (NSArray *)downloadClientAssets {
    NSMutableArray *tasks = [NSMutableArray new];
    NSDictionary *assets = self.metadata[@"assetIndexObj"];
    if (!assets) {
        return @[];
    }
    for (NSString *name in assets[@"objects"]) {
        NSDictionary *object = assets[@"objects"][name];
        NSString *hash = object[@"hash"];
        NSString *pathname = [NSString stringWithFormat:@"%@/%@", [hash substringToIndex:2], hash];
        NSUInteger size = [object[@"size"] unsignedLongLongValue];

        NSString *path;
        if ([assets[@"map_to_resources"] boolValue]) {
            path = [NSString stringWithFormat:@"%s/resources/%@", getenv("POJAV_GAME_DIR"), name];
        } else {
            path = [NSString stringWithFormat:@"%s/assets/objects/%@", getenv("POJAV_GAME_DIR"), pathname];
        }

        /* Special case for 1.19+
         * Since 1.19-pre1, setting the window icon on macOS invokes ObjC.
         * However, if an IOException occurs, it won't try to set.
         * We skip downloading the icon file to workaround this. */
        if ([name hasSuffix:@"/minecraft.icns"]) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            continue;
        }

        NSString *url = [NSString stringWithFormat:@"https://resources.download.minecraft.net/%@", pathname];
        NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:hash altName:name toPath:path success:nil];
        if (task) {
            [tasks addObject:task];
        } else if (self.progress.cancelled) {
            return nil;
        }
    }
    return tasks;
}

- (void)downloadVersion:(NSDictionary *)version {
    [self prepareForDownload];
    if (!getPrefBool(@"general.check_sha")) {
        NSString *versionId = version[@"id"];
        if ([versionId isEqualToString:@"latest-release"]) {
            versionId = getPrefObject(@"internal.latest_version.release");
        } else if ([versionId isEqualToString:@"latest-snapshot"]) {
            versionId = getPrefObject(@"internal.latest_version.snapshot");
        }
        NSString *path = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json",
            getenv("POJAV_GAME_DIR"), versionId];
        NSMutableDictionary *local = parseJSONFromFile(path);
        if (!local || local[@"NSErrorObject"]) {
            [self finishDownloadWithErrorString:localize(@"本地版本文件缺失；完整性检查已关闭，未进行联网修复。", nil)];
            return;
        }
        NSString *parentId = local[@"inheritsFrom"];
        if (parentId.length) {
            NSString *parentPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json",
                getenv("POJAV_GAME_DIR"), parentId];
            NSMutableDictionary *parent = parseJSONFromFile(parentPath);
            if (!parent || parent[@"NSErrorObject"]) {
                [self finishDownloadWithErrorString:localize(@"本地基础版本文件缺失；完整性检查已关闭，未进行联网修复。", nil)];
                return;
            }
            [MinecraftResourceUtils processVersion:local inheritsFrom:parent];
            local = parent;
        }
        self.metadata = local;
        [MinecraftResourceUtils tweakVersionJson:self.metadata];
        if (self.downloadPlanReady) self.downloadPlanReady(NO);
        self.progress.totalUnitCount = 1;
        self.progress.completedUnitCount = 1;
        self.textProgress.totalUnitCount = 1;
        self.textProgress.completedUnitCount = 1;
        return;
    }
    [self downloadVersionMetadata:version success:^{
        // Integrity-off means existing files are trusted; missing files must
        // still be enumerated and downloaded, especially immediately after a
        // Forge installer has produced only its version JSON.
        [self downloadAssetMetadataWithSuccess:^{
            NSArray *libTasks = [self downloadClientLibraries];
            NSArray *assetTasks = [self downloadClientAssets];
            if (self.downloadPlanReady) {
                self.downloadPlanReady(self.fileList.count > 0);
            }
            // Drop the 1 byte we set initially
            self.progress.totalUnitCount--;
            self.textProgress.totalUnitCount--;
            if (self.progress.totalUnitCount == 0) {
                // We have nothing to download, invoke completion observer
                self.progress.totalUnitCount = 1;
                self.progress.completedUnitCount = 1;
                self.textProgress.totalUnitCount = 1;
                self.textProgress.completedUnitCount = 1;
                return;
            }
            [libTasks makeObjectsPerformSelector:@selector(resume)];
            [assetTasks makeObjectsPerformSelector:@selector(resume)];
            [self.metadata removeObjectForKey:@"assetIndexObj"];
        }];
    }];
}

#pragma mark - Modpack installation

- (void)downloadModpackFromAPI:(ModpackAPI *)api detail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion {
    [self prepareForDownload];

    NSString *url = modDetail[@"versionUrls"][selectedVersion];
    NSUInteger size = [modDetail[@"versionSizes"][selectedVersion] unsignedLongLongValue];
    NSString *sha = modDetail[@"versionHashes"][selectedVersion];
    NSString *name = [[modDetail[@"title"] lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    name = [name stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    NSString *cacheRoot = [@(getenv("POJAV_GAME_DIR"))
        stringByAppendingPathComponent:@".pocketj-cache/modpacks"];
    NSString *packagePath = [cacheRoot stringByAppendingPathComponent:
        [name stringByAppendingPathExtension:@"zip"]];

    NSURLSessionDownloadTask *task = [self createDownloadTask:url size:size sha:sha altName:nil toPath:packagePath success:^{
        NSString *relative = PLProfiles.current.selectedProfile[@"gameDir"] ?: @"";
        if ([relative hasPrefix:@"./"]) relative = [relative substringFromIndex:2];
        NSString *path = relative.length
            ? [@(getenv("POJAV_GAME_DIR")) stringByAppendingPathComponent:relative]
            : [NSString stringWithFormat:@"%s/custom_gamedir/%@", getenv("POJAV_GAME_DIR"), name];
        [api downloader:self submitDownloadTasksFromPackage:packagePath toPath:path];

        // The download plan starts with one sentinel unit so that the package
        // download cannot finish the whole operation before its contents have
        // been inspected. Once every dependency has been queued, remove that
        // sentinel. The progress can now finish naturally when the remaining
        // files complete (or immediately when all files were reused).
        @synchronized (self) {
            self.progress.totalUnitCount = MAX(0, self.progress.totalUnitCount - 1);
            self.textProgress.totalUnitCount = self.progress.totalUnitCount;
            if (self.progress.totalUnitCount == 0) {
                self.progress.totalUnitCount = 1;
                self.progress.completedUnitCount = 1;
                self.textProgress.totalUnitCount = 1;
                self.textProgress.completedUnitCount = 1;
            }
        }
    }];
    [task resume];
}

#pragma mark - Utilities

- (void)prepareForDownload {
    // Create a fake progress which is used to update completedUnitCount properly
    // (completedUnitCount does not update unless subprogress completes)
    self.textProgress = [NSProgress new];
    self.textProgress.kind = NSProgressKindFile;
    self.textProgress.fileOperationKind = NSProgressFileOperationKindDownloading;
    self.textProgress.totalUnitCount = -1;
    self.textProgress.pausable = YES;

    self.progress = [NSProgress new];
    self.progress.pausable = YES;
    // Push 1 byte so it won't accidentally finish after downloading assets index
    self.progress.totalUnitCount = 1;
    @synchronized (self) {
        [self.fileList removeAllObjects];
        [self.progressList removeAllObjects];
    }
}

- (void)snapshotFileList:(NSArray **)files progressList:(NSArray **)progresses {
    @synchronized (self) {
        NSUInteger count = MIN(self.fileList.count, self.progressList.count);
        if (files) *files = [self.fileList subarrayWithRange:NSMakeRange(0, count)];
        if (progresses) *progresses = [self.progressList subarrayWithRange:NSMakeRange(0, count)];
    }
}

- (void)cancel {
    [self.progress cancel];
    [self.textProgress cancel];
    [self.manager invalidateSessionCancelingTasks:YES resetSession:YES];
}

- (void)setNetworkTasksSuspended:(BOOL)suspended {
    [self.manager.session
        getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
            for (NSURLSessionTask *task in tasks) {
                if (suspended) {
                    [task suspend];
                } else {
                    [task resume];
                }
            }
        }];
}

- (void)pause {
    [self setNetworkTasksSuspended:YES];
    [self.progress pause];
    [self.textProgress pause];
}

- (void)resume {
    [self setNetworkTasksSuspended:NO];
    [self.progress resume];
    [self.textProgress resume];
}

- (void)finishDownloadWithErrorString:(NSString *)error {
    @synchronized (self) {
        if (self.terminalFailureDelivered) return;
        self.terminalFailureDelivered = YES;
    }
    [self.progress cancel];
    [self.manager invalidateSessionCancelingTasks:YES resetSession:YES];
    showDialog(localize(@"Error", nil), error);
    if (self.handleError) self.handleError();
}

- (void)finishDownloadWithError:(NSError *)error file:(NSString *)file {
    NSString *errorStr = [NSString stringWithFormat:localize(@"launcher.mcl.error_download", NULL), file, error.localizedDescription];
    NSLog(@"[MCDL] Error: %@ %@", errorStr, NSThread.callStackSymbols);
    [self finishDownloadWithErrorString:errorStr];
}

// Check if the account has permission to download
- (BOOL)checkAccessWithDialog:(BOOL)show {
    // A selected local/offline account is sufficient for the launcher download
    // and startup flow. Microsoft authentication remains optional.
    BOOL accessible =
        BaseAuthenticator.current != nil &&
        [BaseAuthenticator.current.authData[@"username"] length] > 0;
    if (!accessible) {
        [self.progress cancel];
        if (show) {
            [self finishDownloadWithErrorString:localize(@"请先选择一个本地账户或 Microsoft 账户。", nil)];
        }
    }
    return accessible;
}

// Check SHA of the file
- (BOOL)checkSHAIgnorePref:(NSString *)sha forFile:(NSString *)path altName:(NSString *)altName logSuccess:(BOOL)logSuccess {
    if (sha.length == 0) {
        // When sha = skip, only check for file existence
        BOOL existence = [NSFileManager.defaultManager fileExistsAtPath:path];
        if (existence) {
            NSLog(@"[MCDL] Warning: couldn't find SHA for %@, have to assume it's good.", path);
        }
        return existence;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        NSLog(@"[MCDL] SHA1 checker: file doesn't exist: %@", altName ? altName : path.lastPathComponent);
        return NO;
    }

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *localSHA = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [localSHA appendFormat:@"%02x", digest[i]];
    }

    BOOL check = [sha isEqualToString:localSHA];
    if (!check || (getPrefBool(@"general.debug_logging") && logSuccess)) {
        NSLog(@"[MCDL] SHA1 %@ for %@%@",
          (check ? @"passed" : @"failed"), 
          (altName ? altName : path.lastPathComponent),
          (check ? @"" : [NSString stringWithFormat:@" (expected: %@, got: %@)", sha, localSHA]));
    }
    return check;
}

- (BOOL)checkSHA:(NSString *)sha forFile:(NSString *)path altName:(NSString *)altName logSuccess:(BOOL)logSuccess {
    if (getPrefBool(@"general.check_sha")) {
        return [self checkSHAIgnorePref:sha forFile:path altName:altName logSuccess:logSuccess];
    } else {
        return [NSFileManager.defaultManager fileExistsAtPath:path];
    }
}

- (BOOL)checkSHA:(NSString *)sha forFile:(NSString *)path altName:(NSString *)altName {
    return [self checkSHA:sha forFile:path altName:altName logSuccess:altName==nil];
}

@end
