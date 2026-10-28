#import "PocketJArchiveService.h"
#import "PocketJModStore.h"
#import "PocketJInstanceContext.h"
#import "UnzipKit.h"
#include <sys/stat.h>
static NSError *PJArchiveError(NSString *text) { return [NSError errorWithDomain:@"PocketJ.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(text,nil)}]; }
static BOOL PJArchiveName(NSString *name) {
    if (!name.length || [name hasPrefix:@"/"] || [name containsString:@"\\"] || [name containsString:@":"]) return NO;
    for (NSString *part in name.pathComponents) if ([part isEqual:@".."] || [part isEqual:@"."]) return NO;
    return YES;
}
@implementation PocketJArchiveService
+ (BOOL)validateArchive:(NSString *)path error:(NSError **)error {
    UZKArchive *archive=[[UZKArchive alloc] initWithPath:path error:error];
    NSArray<UZKFileInfo *> *entries=[archive listFileInfo:error];
    if (!entries.count || entries.count>100000) { if (error && !*error) *error=PJArchiveError(@"Invalid archive or too many files."); return NO; }
    unsigned long long total=0; NSMutableSet *names=[NSMutableSet set];
    for (UZKFileInfo *entry in entries) {
        total+=entry.uncompressedSize;
        if (!PJArchiveName(entry.filename) || (entry.posixPermissions & S_IFMT)==S_IFLNK || entry.isEncryptedWithPassword || total>4ULL*1024*1024*1024 || [names containsObject:entry.filename]) {
            if (error) *error=PJArchiveError(@"Unsafe, encrypted, duplicate or oversized archive entries."); return NO;
        }
        [names addObject:entry.filename];
    }
    return YES;
}
+ (BOOL)installWorld:(NSURL *)url saves:(NSString *)saves name:(NSString *)name error:(NSError **)error {
    if (![self validateArchive:url.path error:error]) return NO;
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *stage=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![fm createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    UZKArchive *archive=[[UZKArchive alloc] initWithURL:url error:error];
    if (![archive extractFilesTo:stage overwrite:NO error:error]) { [fm removeItemAtPath:stage error:nil]; return NO; }
    NSMutableArray *worlds=[NSMutableArray array];
    NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:stage];
    for (NSString *relative in enumerator) if ([relative.lastPathComponent isEqual:@"level.dat"] && ![relative.pathComponents containsObject:@"__MACOSX"]) [worlds addObject:[stage stringByAppendingPathComponent:relative.stringByDeletingLastPathComponent]];
    if (worlds.count!=1 || ![PocketJModStore isSafeFileName:name]) { [fm removeItemAtPath:stage error:nil]; if (error) *error=PJArchiveError(@"Choose a ZIP containing exactly one world (level.dat), with a valid world name."); return NO; }
    [fm createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:error];
    NSString *destination=[saves stringByAppendingPathComponent:name];
    BOOL success=[fm moveItemAtPath:worlds.firstObject toPath:destination error:error];
    // When level.dat is at the ZIP root, stage itself was moved successfully.
    if ([fm fileExistsAtPath:stage]) [fm removeItemAtPath:stage error:nil];
    return success;
}
+ (NSURL *)output:(NSString *)name extension:(NSString *)ext error:(NSError **)error {
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *safe=[PocketJModStore isSafeFileName:name] ? name:@"PocketJ";
    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:[safe stringByAppendingPathExtension:ext]]];
}
+ (BOOL)addTree:(NSString *)root archive:(UZKArchive *)archive prefix:(NSString *)prefix included:(NSSet *)included excluded:(NSSet *)excluded error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;
    for (NSString *relative in [fm enumeratorAtPath:root]) {
        if (included && ![included containsObject:relative.pathComponents.firstObject]) continue;
        if ([excluded containsObject:relative]) continue;
        NSString *path=[root stringByAppendingPathComponent:relative];
        NSDictionary *attributes=[fm attributesOfItemAtPath:path error:error]; if (!attributes) return NO;
        if (![attributes[NSFileType] isEqual:NSFileTypeRegular]) continue;
        // Sidecar state, resume blobs and platform metadata are not game assets.
        BOOL hidden=NO; for (NSString *part in relative.pathComponents) if ([part hasPrefix:@"."] || [part isEqual:@"session.lock"]) hidden=YES;
        if (hidden) continue;
        NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
        NSString *name=prefix.length ? [prefix stringByAppendingPathComponent:relative]:relative;
        if (!data || ![archive writeData:data filePath:name error:error]) return NO;
    }
    return YES;
}
+ (NSURL *)exportWorld:(NSString *)path error:(NSError **)error {
    if (![NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathComponent:@"level.dat"]]) { if (error) *error=PJArchiveError(@"This folder is not a Minecraft world."); return nil; }
    NSURL *url=[self output:path.lastPathComponent extension:@"zip" error:error]; if (!url) return nil;
    UZKArchive *archive=[[UZKArchive alloc] initWithURL:url error:error];
    if (![self addTree:path archive:archive prefix:path.lastPathComponent included:nil excluded:nil error:error]) { [NSFileManager.defaultManager removeItemAtURL:url error:nil]; return nil; }
    return url;
}
+ (NSURL *)exportInstance:(NSString *)path name:(NSString *)name format:(NSString *)format error:(NSError **)error {
    if (![@[@"zip",@"mrpack",@"curseforge",@"multimc",@"links"] containsObject:format]) { if (error) *error=PJArchiveError(@"Unknown export format."); return nil; }
    PocketJInstanceContext *context=[[PocketJInstanceContext alloc] initWithInstancePath:path];
    if (!context.minecraftVersion.length) { if (error) *error=PJArchiveError(@"Select a concrete Minecraft version before exporting."); return nil; }
    PocketJModStore *store=[[PocketJModStore alloc] initWithInstancePath:path];
    NSArray *mods=[store scan:error]; if (error && *error) return nil;
    NSMutableDictionary *dependencies=[@{@"minecraft":context.minecraftVersion} mutableCopy];
    NSString *loaderVersion=context.profile[@"pocketjLoaderVersion"];
    if (![context.loader isEqual:@"vanilla"] && loaderVersion.length) dependencies[[context.loader stringByAppendingString:@"-loader"]]=loaderVersion;
    if ([context.loader isEqual:@"forge"] || [context.loader isEqual:@"neoforge"]) { [dependencies removeObjectForKey:[context.loader stringByAppendingString:@"-loader"]]; if (loaderVersion.length) dependencies[context.loader]=loaderVersion; }
    NSURL *output=[self output:name extension:[format isEqual:@"links"] ? @"txt":([format isEqual:@"mrpack"] ? @"mrpack":@"zip") error:error]; if (!output) return nil;
    NSMutableArray *mrFiles=[NSMutableArray array], *cfFiles=[NSMutableArray array], *links=[NSMutableArray array];
    NSMutableSet *exclude=[NSMutableSet set];
    for (NSDictionary *mod in mods) {
        NSDictionary *download=mod[@"download"]; NSString *url=download[@"url"], *file=mod[@"fileName"];
        if (url.length) [links addObject:[NSString stringWithFormat:@"%@\t%@",file,url]];
        if ([format isEqual:@"mrpack"] && [mod[@"provider"] isEqual:@"Modrinth"] && url.length && [mod[@"enabled"] boolValue] && [download[@"hashes"][@"sha1"] length] && [download[@"hashes"][@"sha512"] length]) {
            [mrFiles addObject:@{@"path":[@"mods" stringByAppendingPathComponent:file],@"hashes":download[@"hashes"],@"downloads":@[url],@"fileSize":download[@"size"] ?: @0,@"env":@{@"client":@"required",@"server":@"optional"}}];
            [exclude addObject:[@"mods" stringByAppendingPathComponent:file]];
        }
        if ([format isEqual:@"curseforge"] && [mod[@"provider"] isEqual:@"CurseForge"] && [mod[@"enabled"] boolValue] && [mod[@"projectID"] longLongValue] && [mod[@"versionID"] longLongValue]) {
            [cfFiles addObject:@{@"projectID":@([mod[@"projectID"] longLongValue]),@"fileID":@([mod[@"versionID"] longLongValue]),@"required":@YES}]; [exclude addObject:[@"mods" stringByAppendingPathComponent:file]];
        }
    }
    if ([format isEqual:@"links"]) {
        NSString *text=[NSString stringWithFormat:@"# PocketJ %@ / Minecraft %@\n# Only files with known download sources are listed.\n%@\n",name,context.minecraftVersion,[links componentsJoinedByString:@"\n"]];
        if (![text writeToURL:output atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil; return output;
    }
    UZKArchive *archive=[[UZKArchive alloc] initWithURL:output error:error]; if (!archive) return nil;
    NSString *prefix=[format isEqual:@"multimc"] ? @".minecraft":(( [format isEqual:@"mrpack"] || [format isEqual:@"curseforge"]) ? @"overrides":@"");
    NSSet *include=[NSSet setWithArray:@[@"mods",@"config",@"defaultconfigs",@"resourcepacks",@"shaderpacks",@"saves",@"datapacks",@"options.txt",@"servers.dat"]];
    if (![self addTree:path archive:archive prefix:prefix included:include excluded:exclude error:error]) return nil;
    NSDictionary *manifest; NSString *manifestName;
    if ([format isEqual:@"mrpack"]) { manifest=@{@"formatVersion":@1,@"game":@"minecraft",@"versionId":@"1.0",@"name":name,@"files":mrFiles,@"dependencies":dependencies}; manifestName=@"modrinth.index.json"; }
    else if ([format isEqual:@"curseforge"]) {
        NSMutableArray *loaders=[NSMutableArray array]; if (loaderVersion.length && ![context.loader isEqual:@"vanilla"]) [loaders addObject:@{@"id":[NSString stringWithFormat:@"%@-%@",context.loader,loaderVersion],@"primary":@YES}];
        manifest=@{@"minecraft":@{@"version":context.minecraftVersion,@"modLoaders":loaders},@"manifestType":@"minecraftModpack",@"manifestVersion":@1,@"name":name,@"version":@"1.0",@"author":@"",@"files":cfFiles,@"overrides":@"overrides"}; manifestName=@"manifest.json";
    } else if ([format isEqual:@"multimc"]) {
        NSMutableArray *components=[NSMutableArray arrayWithObject:@{@"uid":@"net.minecraft",@"version":context.minecraftVersion}];
        NSDictionary *uids=@{@"fabric":@"net.fabricmc.fabric-loader",@"quilt":@"org.quiltmc.quilt-loader",@"forge":@"net.minecraftforge",@"neoforge":@"net.neoforged"};
        if (uids[context.loader] && loaderVersion.length) [components addObject:@{@"uid":uids[context.loader],@"version":loaderVersion}];
        manifest=@{@"formatVersion":@1,@"components":components}; manifestName=@"mmc-pack.json";
        NSString *cfg=[NSString stringWithFormat:@"[General]\nname=%@\nInstanceType=OneSix\n",[name stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
        if (![archive writeData:[cfg dataUsingEncoding:NSUTF8StringEncoding] filePath:@"instance.cfg" error:error]) return nil;
    } else {
        // A portable PocketJ archive gets a minimal profile, never absolute Java
        // paths, selected accounts, tokens, pairing files or local credentials.
        NSMutableDictionary *profile=[@{@"name":name,@"lastVersionId":context.minecraftVersion,@"pocketjMinecraftVersion":context.minecraftVersion,@"pocketjLoader":context.loader} mutableCopy];
        if (loaderVersion.length) profile[@"pocketjLoaderVersion"]=loaderVersion;
        manifest=@{@"selectedProfile":@"default",@"profiles":@{@"default":profile}}; manifestName=@"launcher_profiles.json";
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:error];
    if (!json || ![archive writeData:json filePath:manifestName error:error]) return nil;
    return output;
}
@end
