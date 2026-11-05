#include "PocketJEnvironment.h"
#import "PocketJModSearchIndex.h"
#import <CoreFoundation/CoreFoundation.h>
@interface PocketJModSearchIndex ()
@property(nonatomic) NSArray<NSDictionary *> *entries;
@end
@implementation PocketJModSearchIndex
+ (instancetype)shared { static id index; static dispatch_once_t once; dispatch_once(&once,^{ index=[self new]; }); return index; }
- (instancetype)init {
    if ((self=[super init])) {
        NSData *data=[NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"pocketj-mod-aliases" withExtension:@"json"]];
        id entries=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        _entries=[entries isKindOfClass:NSArray.class] ? entries:@[];
    }
    return self;
}
- (NSString *)onlineQuery:(NSString *)query installed:(NSArray<NSDictionary *> *)installed {
    NSString *clean=[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![clean rangeOfString:@"[\\p{Han}]" options:NSRegularExpressionSearch].length) return clean;
    NSMutableString *canonicalQuery = [clean mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)canonicalQuery, NULL,
        CFSTR("Traditional-Simplified"), false);
    NSMutableArray *entries; @synchronized (self) { entries=[self.entries mutableCopy]; }
    for (NSDictionary *mod in installed) if ([mod[@"name"] length] && [mod[@"alias"] length]) [entries addObject:@{@"aliases":@[mod[@"alias"]],@"query":mod[@"name"]}];
    NSDictionary *best=nil; NSUInteger score=0;
    for (NSDictionary *entry in entries) {
        for (NSString *alias in entry[@"aliases"]) {
            if (![alias isKindOfClass:NSString.class] || !alias.length) continue;
            NSMutableString *canonicalAlias = [alias mutableCopy];
            CFStringTransform((__bridge CFMutableStringRef)canonicalAlias, NULL,
                CFSTR("Traditional-Simplified"), false);
            if (canonicalAlias.length==1 && ![canonicalQuery isEqual:canonicalAlias]) continue;
            NSRange match=[canonicalQuery rangeOfString:canonicalAlias options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
            if (match.location!=NSNotFound && canonicalAlias.length>score) { score=canonicalAlias.length; best=entry; }
        }
    }
    // Resolve a known Chinese name to its English project query, but do not
    // replace arbitrary Chinese input with an unrelated built-in default.
    return [best[@"query"] length] ? best[@"query"]:clean;
}
@end
