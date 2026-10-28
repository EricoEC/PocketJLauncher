#import "PocketJModStore.h"
#include <CommonCrypto/CommonDigest.h>
#if __has_include("UnzipKit.h")
#import "UnzipKit.h"
#define PJ_HAS_ARCHIVE 1
#else
#define PJ_HAS_ARCHIVE 0
#endif

static NSError *PJStoreError(NSString *message) {
    return [NSError errorWithDomain:@"PocketJ.ModStore" code:1
        userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(message,nil)}];
}
static id PJPropertyListValue(id object) {
    if (object == NSNull.null) return nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *clean=[NSMutableDictionary dictionary];
        for (id key in object) { id value=PJPropertyListValue(object[key]); if ([key isKindOfClass:NSString.class] && value) clean[key]=value; }
        return clean;
    }
    if ([object isKindOfClass:NSArray.class]) {
        NSMutableArray *clean=[NSMutableArray array]; for (id child in object) { id value=PJPropertyListValue(child); if (value) [clean addObject:value]; } return clean;
    }
    return object;
}
@interface PocketJModStore ()
@property(nonatomic) NSString *instancePath;
@property(nonatomic) NSString *modsPath;
@property(nonatomic) NSString *instanceID;
@property(nonatomic) NSString *catalogPath;
@end

@implementation PocketJModStore
- (instancetype)initWithInstancePath:(NSString *)path {
    if ((self = [super init])) {
        _instancePath = path.stringByStandardizingPath;
        _modsPath = [_instancePath stringByAppendingPathComponent:@"mods"];
        _catalogPath = [_instancePath stringByAppendingPathComponent:@".pocketj-mods.plist"];
        NSString *identityPath = [_instancePath stringByAppendingPathComponent:@".pocketj-instance-id"];
        _instanceID = [NSString stringWithContentsOfFile:identityPath encoding:NSUTF8StringEncoding error:nil];
        _instanceID=[_instanceID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!_instanceID.length) {
            _instanceID = NSUUID.UUID.UUIDString;
            [NSFileManager.defaultManager createDirectoryAtPath:_instancePath withIntermediateDirectories:YES attributes:nil error:nil];
            [_instanceID writeToFile:identityPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
    return self;
}
+ (BOOL)isSafeFileName:(NSString *)name {
    return name.length && ![name hasPrefix:@"."] &&
        [name isEqualToString:name.lastPathComponent] &&
        [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:\n\r"]].location == NSNotFound;
}
- (NSString *)pathForFile:(NSString *)name {
    if (![PocketJModStore isSafeFileName:name]) return nil;
    NSString *path = [self.modsPath stringByAppendingPathComponent:name];
    // External symlinks are never followed for exports, updates or hashing.
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [attrs[NSFileType] isEqual:NSFileTypeSymbolicLink] ? nil : path;
}
- (NSMutableDictionary *)catalog {
    return [[NSDictionary dictionaryWithContentsOfFile:self.catalogPath] mutableCopy] ?: [NSMutableDictionary dictionary];
}
- (BOOL)saveCatalog:(NSDictionary *)catalog error:(NSError **)error {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:PJPropertyListValue(catalog)
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [data writeToFile:self.catalogPath options:NSDataWritingAtomic error:error];
}
+ (NSString *)sha1AtPath:(NSString *)path {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    [stream open];
    CC_SHA1_CTX context; CC_SHA1_Init(&context);
    uint8_t buffer[65536]; NSInteger count;
    while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) CC_SHA1_Update(&context, buffer, (CC_LONG)count);
    [stream close];
    if (count < 0 || stream.streamError) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH]; CC_SHA1_Final(digest, &context);
    NSMutableString *hash = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [hash appendFormat:@"%02x", digest[i]];
    return hash;
}
+ (BOOL)validateJarAtPath:(NSString *)path error:(NSError **)error {
#if PJ_HAS_ARCHIVE
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:error];
    NSArray *files = archive ? [archive listFilenames:error] : nil;
    if (!files.count) { if (error && !*error) *error = PJStoreError(@"Invalid or empty JAR archive."); return NO; }
    return YES;
#else
    // Foundation-only test harness; production always links UnzipKit.
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *magic = [handle readDataOfLength:4]; [handle closeFile];
    const unsigned char signature[] = {0x50, 0x4b, 0x03, 0x04};
    BOOL valid = [magic isEqualToData:[NSData dataWithBytes:signature length:4]];
    if (!valid && error) *error = PJStoreError(@"Invalid JAR archive.");
    return valid;
#endif
}
- (NSDictionary *)embeddedMetadata:(NSString *)path {
#if PJ_HAS_ARCHIVE
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:nil];
    for (NSString *entry in @[@"fabric.mod.json", @"quilt.mod.json", @"mcmod.info"]) {
        NSData *data = [archive extractDataFromFile:entry error:nil];
        if (!data || data.length > 1024 * 1024) continue;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([object isKindOfClass:NSArray.class]) object = [object firstObject];
        if (![object isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *root = object;
        NSDictionary *quilt = root[@"quilt_loader"];
        if ([quilt isKindOfClass:NSDictionary.class]) root = quilt;
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        id modID = root[@"id"] ?: root[@"modid"];
        NSDictionary *details=[root[@"metadata"] isKindOfClass:NSDictionary.class] ? root[@"metadata"] : @{};
        id name = details[@"name"] ?: root[@"name"];
        id version = root[@"version"];
        if ([modID isKindOfClass:NSString.class]) result[@"modID"] = modID;
        if ([name isKindOfClass:NSString.class]) result[@"name"] = name;
        if ([version isKindOfClass:NSString.class]) result[@"version"] = version;
        NSMutableArray *requires=[NSMutableArray array];
        if ([root[@"depends"] isKindOfClass:NSDictionary.class]) [requires addObjectsFromArray:[root[@"depends"] allKeys]];
        else if ([root[@"depends"] isKindOfClass:NSArray.class]) for (id entry in root[@"depends"]) {
            if ([entry isKindOfClass:NSDictionary.class] && [entry[@"id"] isKindOfClass:NSString.class]) [requires addObject:entry[@"id"]];
        }
        result[@"embeddedRequires"]=requires;
        return result;
    }
    for (NSString *entry in @[@"META-INF/neoforge.mods.toml", @"META-INF/mods.toml"]) {
        NSData *data = [archive extractDataFromFile:entry error:nil];
        if (!data || data.length > 1024 * 1024) continue;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) continue;
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"modId", @"displayName", @"version"]) {
            NSString *pattern = [NSString stringWithFormat:@"(?m)^\\s*%@\\s*=\\s*[\"']([^\"'\\r\\n]+)[\"']", key];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
            if (match) result[@{@"modId":@"modID", @"displayName":@"name", @"version":@"version"}[key]] = [text substringWithRange:[match rangeAtIndex:1]];
        }
        return result;
    }
#endif
    return @{};
}
- (NSArray<NSDictionary *> *)scan:(NSError **)error {
    @synchronized (PocketJModStore.class) {
        if (![NSFileManager.defaultManager createDirectoryAtPath:self.modsPath withIntermediateDirectories:YES attributes:nil error:error]) return @[];
        NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.modsPath error:error];
        if (!files) return @[];
        NSMutableDictionary *catalog = [self catalog];
        NSMutableSet *present = [NSMutableSet set];
        NSMutableArray *result = [NSMutableArray array];
        for (NSString *file in files) {
            NSString *lower = file.lowercaseString;
            if (![lower hasSuffix:@".jar"] && ![lower hasSuffix:@".jar.disabled"]) continue;
            NSString *path = [self pathForFile:file];
            NSDictionary *attributes = path ? [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] : nil;
            if (![attributes[NSFileType] isEqual:NSFileTypeRegular]) continue;
            NSMutableDictionary *record = [catalog[file] mutableCopy] ?: [NSMutableDictionary dictionary];
            NSString *stamp = [NSString stringWithFormat:@"%@/%@", attributes[NSFileSize], attributes[NSFileModificationDate]];
            if (![record[@"stamp"] isEqual:stamp]) {
                NSDictionary *embedded = [self embeddedMetadata:path];
                [record addEntriesFromDictionary:embedded];
                record[@"sha1"] = [PocketJModStore sha1AtPath:path] ?: @"";
                record[@"stamp"] = stamp;
            }
            if (!record[@"id"]) record[@"id"] = NSUUID.UUID.UUIDString;
            record[@"fileName"] = file;
            record[@"enabled"] = @(![lower hasSuffix:@".disabled"]);
            NSString *base = [lower hasSuffix:@".disabled"] ? file.stringByDeletingPathExtension : file;
            record[@"title"] = [record[@"alias"] length] ? record[@"alias"] : (record[@"name"] ?: base.stringByDeletingPathExtension);
            catalog[file] = record;
            [present addObject:file]; [result addObject:record];
        }
        for (NSString *key in catalog.allKeys) if (![present containsObject:key]) [catalog removeObjectForKey:key];
        if (![self saveCatalog:catalog error:error]) return @[];
        [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"title"] localizedStandardCompare:b[@"title"]]; }];
        return result;
    }
}
- (NSDictionary *)recordForFile:(NSString *)file {
    @synchronized (PocketJModStore.class) { return [self catalog][file]; }
}
- (BOOL)annotateFile:(NSString *)file values:(NSDictionary *)values error:(NSError **)error {
    @synchronized (PocketJModStore.class) {
        NSMutableDictionary *catalog = [self catalog];
        NSMutableDictionary *record = [catalog[file] mutableCopy];
        if (!record) { if (error) *error = PJStoreError(@"The mod no longer exists."); return NO; }
        for (NSString *key in @[@"alias", @"notes", @"updateLocked", @"provider", @"projectID", @"versionID", @"download", @"dependencies"]) {
            if (values[key]) record[key] = values[key];
        }
        catalog[file] = record;
        return [self saveCatalog:catalog error:error];
    }
}
- (BOOL)renameFile:(NSString *)file to:(NSString *)name error:(NSError **)error {
    @synchronized (PocketJModStore.class) {
        NSString *oldPath = [self pathForFile:file], *newPath = [self pathForFile:name];
        if (!oldPath || !newPath ||
            (![name.lowercaseString hasSuffix:@".jar"] && ![name.lowercaseString hasSuffix:@".jar.disabled"])) {
            if (error) *error = PJStoreError(@"Use a valid .jar or .jar.disabled filename."); return NO;
        }
        if ([file isEqual:name]) return YES;
        if (![NSFileManager.defaultManager moveItemAtPath:oldPath toPath:newPath error:error]) return NO;
        NSMutableDictionary *catalog = [self catalog];
        NSMutableDictionary *record = [catalog[file] mutableCopy];
        if (record) { record[@"fileName"] = name; catalog[name] = record; [catalog removeObjectForKey:file]; }
        if ([self saveCatalog:catalog error:error]) return YES;
        [NSFileManager.defaultManager moveItemAtPath:newPath toPath:oldPath error:nil];
        return NO;
    }
}
- (BOOL)setEnabled:(BOOL)enabled file:(NSString *)file error:(NSError **)error {
    BOOL disabled = [file.lowercaseString hasSuffix:@".disabled"];
    NSString *name = enabled ? (disabled ? file.stringByDeletingPathExtension : file)
                            : (disabled ? file : [file stringByAppendingPathExtension:@"disabled"]);
    return [self renameFile:file to:name error:error];
}
- (BOOL)deleteFiles:(NSArray<NSString *> *)files error:(NSError **)error {
    @synchronized (PocketJModStore.class) {
        NSMutableDictionary *catalog = [self catalog];
        for (NSString *file in files) {
            NSString *path = [self pathForFile:file];
            if (!path) { if (error) *error = PJStoreError(@"Unsafe mod path."); return NO; }
            if (![NSFileManager.defaultManager removeItemAtPath:path error:error]) { [self saveCatalog:catalog error:nil]; return NO; }
            [catalog removeObjectForKey:file];
        }
        return [self saveCatalog:catalog error:error];
    }
}
- (BOOL)installJar:(NSURL *)source fileName:(NSString *)name replacingFile:(NSString *)oldName metadata:(NSDictionary *)metadata error:(NSError **)error {
    @synchronized (PocketJModStore.class) {
        if (![PocketJModStore isSafeFileName:name] || ![name.lowercaseString hasSuffix:@".jar"] ||
            ![PocketJModStore validateJarAtPath:source.path error:error]) {
            if (error && !*error) *error = PJStoreError(@"Invalid JAR filename or archive."); return NO;
        }
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm createDirectoryAtPath:self.modsPath withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        BOOL disabled = [oldName.lowercaseString hasSuffix:@".disabled"];
        NSString *targetName = disabled ? [name stringByAppendingPathExtension:@"disabled"] : name;
        NSString *target = [self pathForFile:targetName];
        NSString *oldPath = oldName ? [self pathForFile:oldName] : nil;
        if (!target || (oldName && !oldPath)) { if (error) *error = PJStoreError(@"Unsafe mod path."); return NO; }
        if ([fm fileExistsAtPath:target] && ![target isEqual:oldPath]) {
            if (error) *error = PJStoreError(@"A mod with this filename already exists."); return NO;
        }
        NSMutableDictionary *catalog = [self catalog];
        NSMutableDictionary *record = [catalog[oldName ?: targetName] mutableCopy] ?: [NSMutableDictionary dictionary];
        [record addEntriesFromDictionary:metadata];
        record[@"id"] = record[@"id"] ?: NSUUID.UUID.UUIDString;
        record[@"fileName"] = targetName;
        // Stage in the same directory/volume. Existing file is never removed before validation.
        NSString *stage = [self.modsPath stringByAppendingPathComponent:[@".install-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        if (![fm copyItemAtPath:source.path toPath:stage error:error]) return NO;
        // A short-lived transaction rollback link is not a retained version
        // backup. It is removed on commit and protects against metadata/disk errors.
        NSString *rollback=nil;
        if (oldPath && [fm fileExistsAtPath:oldPath]) {
            rollback=[self.modsPath stringByAppendingPathComponent:[@".rollback-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            if (![fm linkItemAtPath:oldPath toPath:rollback error:error]) { [fm removeItemAtPath:stage error:nil]; return NO; }
        }
        BOOL installed;
        if ([fm fileExistsAtPath:target]) installed = [fm replaceItemAtURL:[NSURL fileURLWithPath:target] withItemAtURL:[NSURL fileURLWithPath:stage] backupItemName:nil options:0 resultingItemURL:nil error:error];
        else installed = [fm moveItemAtPath:stage toPath:target error:error];
        if (!installed) { [fm removeItemAtPath:stage error:nil]; if (rollback) [fm removeItemAtPath:rollback error:nil]; return NO; }
        if (oldPath && ![oldPath isEqual:target] && [fm fileExistsAtPath:oldPath]) {
            if (![fm removeItemAtPath:oldPath error:error]) { [fm removeItemAtPath:target error:nil]; if (rollback) [fm removeItemAtPath:rollback error:nil]; return NO; }
        }
        if (oldName) [catalog removeObjectForKey:oldName];
        [record removeObjectForKey:@"stamp"];
        catalog[targetName] = record;
        if (![self saveCatalog:catalog error:error]) {
            [fm removeItemAtPath:target error:nil];
            if (rollback) [fm moveItemAtPath:rollback toPath:oldPath error:nil];
            return NO;
        }
        if (rollback) [fm removeItemAtPath:rollback error:nil];
        return YES;
    }
}
+ (NSArray<NSDictionary *> *)filterMods:(NSArray<NSDictionary *> *)mods query:(NSString *)query {
    NSArray *words = [[query lowercaseString] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [mods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *record, NSDictionary *bindings) {
        NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", record[@"title"] ?: @"", record[@"name"] ?: @"", record[@"fileName"] ?: @"", record[@"modID"] ?: @"", record[@"alias"] ?: @"", record[@"notes"] ?: @""] lowercaseString];
        for (NSString *word in words) if (word.length && [haystack rangeOfString:word options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) return NO;
        return YES;
    }]];
}
@end
