#import "PocketJInstanceContext.h"
static NSDictionary *PJReadObject(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path]; id object=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [object isKindOfClass:NSDictionary.class] ? object:@{};
}
@implementation PocketJInstanceContext
- (instancetype)initWithInstancePath:(NSString *)path {
    if ((self=[super init])) {
        NSDictionary *root=PJReadObject([path stringByAppendingPathComponent:@"launcher_profiles.json"]);
        id profile=root[@"profiles"][root[@"selectedProfile"] ?: @""];
        _profile=[profile isKindOfClass:NSDictionary.class] ? profile:@{};
        NSString *versionID=[_profile[@"lastVersionId"] isKindOfClass:NSString.class] ? _profile[@"lastVersionId"]:@"";
        NSString *lower=versionID.lowercaseString;
        NSString *explicit=[_profile[@"pocketjLoader"] isKindOfClass:NSString.class] ? [_profile[@"pocketjLoader"] lowercaseString]:@"";
        NSArray *known=@[@"vanilla",@"fabric",@"forge",@"neoforge",@"quilt"];
        _loader=[known containsObject:explicit] ? explicit:([lower containsString:@"neoforge"] ? @"neoforge":([lower containsString:@"fabric"] ? @"fabric":([lower containsString:@"quilt"] ? @"quilt":([lower containsString:@"forge"] ? @"forge":@"vanilla"))));
        NSDictionary *version=[PocketJInstanceContext safeVersion:versionID atPath:path];
        id mc=_profile[@"pocketjMinecraftVersion"] ?: version[@"inheritsFrom"];
        _minecraftVersion=[mc isKindOfClass:NSString.class] ? mc:@"";
        if (!_minecraftVersion.length && [_loader isEqual:@"vanilla"]) _minecraftVersion=versionID;
        // Legacy Fabric/Quilt IDs end with the MC version; loader version is
        // deliberately not interpreted as Minecraft's version.
        if (!_minecraftVersion.length && ([_loader isEqual:@"fabric"] || [_loader isEqual:@"quilt"])) {
            NSRegularExpression *suffix=[NSRegularExpression regularExpressionWithPattern:@"-((?:1\\.[0-9]+(?:\\.[0-9]+)?|[2-9][0-9]\\.[0-9]+(?:\\.[0-9]+)?)(?:-(?:snapshot|pre|rc)[-0-9A-Za-z.]*)?|[0-9]{2}w[0-9]{2}[a-z])$" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *match=[suffix firstMatchInString:versionID options:0 range:NSMakeRange(0,versionID.length)];
            if (match) _minecraftVersion=[versionID substringWithRange:[match rangeAtIndex:1]];
        }
        if (!_minecraftVersion) _minecraftVersion=@"";
    }
    return self;
}
+ (NSDictionary *)safeVersion:(NSString *)versionID atPath:(NSString *)path {
    if (!versionID.length || ![versionID isEqual:versionID.lastPathComponent] || [versionID hasPrefix:@"."]) return @{};
    return PJReadObject([[[path stringByAppendingPathComponent:@"versions"] stringByAppendingPathComponent:versionID] stringByAppendingPathComponent:[versionID stringByAppendingPathExtension:@"json"]]);
}
@end
