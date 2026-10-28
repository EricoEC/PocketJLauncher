#include "PocketJEnvironment.h"
#import "PocketJModSearchIndex.h"
@interface PocketJModSearchIndex ()
@property(nonatomic) NSArray<NSDictionary *> *entries;
@property(nonatomic) NSString *path;
@end
@implementation PocketJModSearchIndex
+ (instancetype)shared { static id index; static dispatch_once_t once; dispatch_once(&once,^{ index=[self new]; }); return index; }
- (instancetype)init {
    if ((self=[super init])) {
        NSString *home=PocketJGetEnv("POCKETJ_HOME") ? @(PocketJGetEnv("POCKETJ_HOME")):NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
        _path=[home stringByAppendingPathComponent:@"mod-search-index.plist"];
        _entries=[NSArray arrayWithContentsOfFile:_path];
        if (!_entries) {
            NSData *data=[NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"pocketj-mod-aliases" withExtension:@"json"]];
            id entries=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            _entries=[entries isKindOfClass:NSArray.class] ? entries:@[];
        }
    }
    return self;
}
- (NSString *)onlineQuery:(NSString *)query installed:(NSArray<NSDictionary *> *)installed {
    NSString *clean=[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![clean rangeOfString:@"[\\p{Han}]" options:NSRegularExpressionSearch].length) return clean;
    NSMutableArray *entries; @synchronized (self) { entries=[self.entries mutableCopy]; }
    for (NSDictionary *mod in installed) if ([mod[@"name"] length] && [mod[@"alias"] length]) [entries addObject:@{@"aliases":@[mod[@"alias"]],@"query":mod[@"name"]}];
    NSDictionary *best=nil; NSUInteger score=0;
    for (NSDictionary *entry in entries) {
        for (NSString *alias in entry[@"aliases"]) {
            if (![alias isKindOfClass:NSString.class] || !alias.length) continue;
            if (alias.length==1 && ![clean isEqual:alias]) continue;
            NSRange match=[clean rangeOfString:alias options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
            if (match.location!=NSNotFound && alias.length>score) { score=alias.length; best=entry; }
        }
    }
    // Resolve a known Chinese name to its English project query, but do not
    // replace arbitrary Chinese input with an unrelated built-in default.
    return [best[@"query"] length] ? best[@"query"]:clean;
}
+ (NSArray<NSArray<NSString *> *> *)parseCSV:(NSString *)text {
    NSMutableArray *rows=[NSMutableArray array], *row=[NSMutableArray array]; NSMutableString *field=[NSMutableString string]; BOOL quoted=NO;
    for (NSUInteger i=0;i<text.length;i++) {
        unichar c=[text characterAtIndex:i];
        if (c=='"') {
            if (quoted && i+1<text.length && [text characterAtIndex:i+1]=='"') { [field appendString:@"\""]; i++; }
            else quoted=!quoted;
        } else if (!quoted && (c==',' || c=='\n' || c=='\r')) {
            [row addObject:field.copy]; [field setString:@""];
            if (c!=',') { [rows addObject:row.copy]; [row removeAllObjects]; if (c=='\r' && i+1<text.length && [text characterAtIndex:i+1]=='\n') i++; }
        } else [field appendFormat:@"%C",c];
    }
    if (field.length || row.count) { [row addObject:field.copy]; [rows addObject:row.copy]; }
    return rows;
}
- (BOOL)importCSV:(NSURL *)url error:(NSError **)error {
    NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error]; if (!data) return NO;
    if (data.length>10*1024*1024) { if (error) *error=[NSError errorWithDomain:@"PocketJ.Search" code:1 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Search index is larger than 10 MB.",nil)}]; return NO; }
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSMutableArray *entries=[NSMutableArray array];
    for (NSArray<NSString *> *row in [PocketJModSearchIndex parseCSV:text ?: @""]) {
        if (row.count<2 || [row.firstObject hasPrefix:@"#"]) continue;
        NSArray *aliases; NSString *query;
        if (row.count>=7) { aliases=[row subarrayWithRange:NSMakeRange(3,row.count-3)]; query=[row[4] length] ? row[4]:([row[2] length] ? row[2]:row[1]); }
        else { aliases=[row[0] componentsSeparatedByString:@"|"]; query=row[1]; }
        if (query.length && aliases.count && ![query isEqual:@"query"]) [entries addObject:@{@"aliases":aliases,@"query":query}];
    }
    if (!entries.count) { if (error) *error=[NSError errorWithDomain:@"PocketJ.Search" code:1 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"No valid aliases,query rows were found in the UTF-8 CSV.",nil)}]; return NO; }
    @synchronized (self) {
        if (![entries writeToFile:self.path atomically:YES]) { if (error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]; return NO; }
        self.entries=entries;
    }
    return YES;
}
@end
