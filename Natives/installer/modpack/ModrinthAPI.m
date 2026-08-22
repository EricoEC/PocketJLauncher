#import "MinecraftResourceDownloadTask.h"
#import "ModrinthAPI.h"
#import "PLProfiles.h"

@implementation ModrinthAPI

- (instancetype)init {
    return [super initWithURL:@"https://api.modrinth.com/v2"];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)modrinthSearchResult {
    int limit = 50;

    NSMutableString *facetString = [NSMutableString new];
    [facetString appendString:@"["];
    [facetString appendFormat:@"[\"project_type:%@\"]", searchFilters[@"isModpack"].boolValue ? @"modpack" : @"mod"];
    if (searchFilters[@"mcVersion"].length > 0) {
        [facetString appendFormat:@",[\"versions:%@\"]", searchFilters[@"mcVersion"]];
    }
    [facetString appendString:@"]"];

    NSDictionary *params = @{
        @"facets": facetString,
        @"query": [searchFilters[@"name"] stringByReplacingOccurrencesOfString:@" " withString:@"+"],
        @"limit": @(limit),
        @"index": @"relevance",
        @"offset": @(modrinthSearchResult.count)
    };
    NSDictionary *response = [self getEndpoint:@"search" params:params];
    if (!response) {
        return nil;
    }

    NSMutableArray *result = modrinthSearchResult ?: [NSMutableArray new];
    for (NSDictionary *hit in response[@"hits"]) {
        BOOL isModpack = [hit[@"project_type"] isEqualToString:@"modpack"];
        [result addObject:@{
            @"apiSource": @(1), // Constant MODRINTH
            @"isModpack": @(isModpack),
            @"id": hit[@"project_id"],
            @"title": hit[@"title"],
            @"description": hit[@"description"],
            @"imageUrl": hit[@"icon_url"]
        }.mutableCopy];
    }
    self.reachedLastPage = result.count >= [response[@"total_hits"] unsignedLongValue];
    return result;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    NSArray *response = [self getEndpoint:[NSString stringWithFormat:@"project/%@/version", item[@"id"]] params:nil];
    if (!response) {
        return;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    NSMutableArray<NSString *> *mcNames = [NSMutableArray new];
    NSMutableArray<NSString *> *urls = [NSMutableArray new];
    NSMutableArray<NSString *> *hashes = [NSMutableArray new];
    NSMutableArray<NSString *> *sizes = [NSMutableArray new];
    [response enumerateObjectsUsingBlock:
  ^(NSDictionary *version, NSUInteger i, BOOL *stop) {
        NSDictionary *file = [version[@"files"] firstObject];
        NSString *mcVersion = [version[@"game_versions"] firstObject];
        if (!file[@"url"] || !mcVersion.length) return;
        [names addObject:version[@"name"] ?: version[@"version_number"] ?: @""];
        [mcNames addObject:mcVersion];
        [sizes addObject:file[@"size"] ?: @0];
        [urls addObject:file[@"url"]];
        NSDictionary *hashesMap = file[@"hashes"];
        [hashes addObject:hashesMap[@"sha1"] ?: @""];
    }];
    item[@"versionNames"] = names;
    item[@"mcVersionNames"] = mcNames;
    item[@"versionSizes"] = sizes;
    item[@"versionUrls"] = urls;
    item[@"versionHashes"] = hashes;
    item[@"versionDetailsLoaded"] = @(YES);
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath {
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:packagePath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to open modpack package: %@", error.localizedDescription]];
        return;
    }

    NSData *indexData = [archive extractDataFromFile:@"modrinth.index.json" error:&error];
    NSDictionary* indexDict = [NSJSONSerialization JSONObjectWithData:indexData options:kNilOptions error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to parse modrinth.index.json: %@", error.localizedDescription]];
        return;
    }

    for (NSDictionary *indexFile in indexDict[@"files"]) {
/*
        if ([indexFile[@"downloads"] count] > 1) {
            [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Unhandled multiple files download %@", indexFile[@"downloads"]]];
            return;
        }
*/
        NSString *url = [indexFile[@"downloads"] firstObject];
        NSString *sha = indexFile[@"hashes"][@"sha1"];
        NSString *path = [destPath stringByAppendingPathComponent:indexFile[@"path"]];
        NSUInteger size = [indexFile[@"fileSize"] unsignedLongLongValue];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url size:size sha:sha altName:nil toPath:path];
        if (task) {
            [task resume];
        } else if (downloader.progress.cancelled) {
            return; // cancelled
        }
    }

    [ModpackUtils archive:archive extractDirectory:@"overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract overrides from modpack package: %@", error.localizedDescription]];
        return;
    }

    [ModpackUtils archive:archive extractDirectory:@"client-overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract client-overrides from modpack package: %@", error.localizedDescription]];
        return;
    }

    // Preserve the verified package cache so retries can rebuild the task list
    // and skip every dependency that is already valid on disk.

    // Download dependency client json (if available)
    NSDictionary<NSString *, NSString *> *depInfo = [ModpackUtils infoForDependencies:indexDict[@"dependencies"]];
    if (depInfo[@"json"]) {
        NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), depInfo[@"id"]];
        // Reserve a progress unit immediately. With an unknown size the task
        // would otherwise be attached only after its response arrives, leaving
        // a small window where the whole modpack appears complete too early.
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:depInfo[@"json"] size:1 sha:nil altName:nil toPath:jsonPath];
        [task resume];
    }
    // TODO: automation for Forge

    // Finish the profile that was registered before the homepage download.
    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
    NSMutableDictionary *profile = PLProfiles.current.selectedProfile;
    if ([profile isKindOfClass:NSMutableDictionary.class]) {
        NSDictionary *dependencies = indexDict[@"dependencies"];
        NSString *minecraftVersion = dependencies[@"minecraft"] ?: @"";
        NSString *loader = @"vanilla";
        NSString *loaderVersion = @"";
        BOOL loaderPending = NO;
        if ([dependencies[@"forge"] length]) {
            loader = @"forge";
            loaderVersion = dependencies[@"forge"];
            loaderPending = YES;
        } else if ([dependencies[@"neoforge"] length]) {
            loader = @"neoforge";
            loaderVersion = dependencies[@"neoforge"];
            loaderPending = YES;
        } else if ([dependencies[@"fabric-loader"] length]) {
            loader = @"fabric";
            loaderVersion = dependencies[@"fabric-loader"];
        } else if ([dependencies[@"quilt-loader"] length]) {
            loader = @"quilt";
            loaderVersion = dependencies[@"quilt-loader"];
        }
        profile[@"lastVersionId"] = loaderPending
            ? minecraftVersion : (depInfo[@"id"] ?: minecraftVersion);
        profile[@"pocketjMinecraftVersion"] = minecraftVersion;
        profile[@"pocketjLoader"] = loader;
        profile[@"pocketjLoaderVersion"] = loaderVersion;
        profile[@"pocketjLoaderInstallPending"] = @(loaderPending);
        NSData *iconData = [NSData dataWithContentsOfFile:tmpIconPath];
        if (iconData.length) {
            profile[@"icon"] = [NSString stringWithFormat:@"data:image/png;base64,%@",
                [iconData base64EncodedStringWithOptions:0]];
        }
        [PLProfiles.current save];
    }
}

@end
