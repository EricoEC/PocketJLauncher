#import "PocketJCrashDiagnostics.h"
@implementation PocketJCrashDiagnostics
+ (NSString *)tailAtPath:(NSString *)path limit:(NSUInteger)limit {
    NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:path]; if (!handle) return @"";
    @try {
        unsigned long long size=[handle seekToEndOfFile]; [handle seekToFileOffset:size>limit ? size-limit:0];
        NSData *data=[handle readDataOfLength:limit]; [handle closeFile];
        NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        // A tail can start midway through a multi-byte UTF-8 character.
        if (!text && data.length>4) { for (NSUInteger skip=1;skip<4 && !text;skip++) text=[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(skip,data.length-skip)] encoding:NSUTF8StringEncoding]; }
        return text ?: @"";
    } @catch (NSException *exception) { [handle closeFile]; return @""; }
}
+ (NSDictionary *)analyze:(NSString *)log {
    NSArray *rules=@[
        @{@"match":@"dlsym(RTLD_DEFAULT, main)",@"kind":@"native-entry",@"title":@"可能原因：Java 启动入口不可见",@"hint":@"请使用包含原生入口导出修复的安装包；这不是模组报错。"},
        @{@"match":@"java.lang.OutOfMemoryError",@"kind":@"heap",@"title":@"可能原因：Java 内存不足",@"hint":@"检查实例内存设置、渲染距离与模组占用；不要超过设备可用内存。"},
        @{@"match":@"Could not reserve enough space",@"kind":@"address-space",@"title":@"可能原因：无法保留虚拟地址空间",@"hint":@"降低分配内存，并检查签名中的扩展虚拟地址空间权限。"},
        @{@"match":@"UnsupportedClassVersionError",@"kind":@"java-version",@"title":@"可能原因：Java 版本不匹配",@"hint":@"检查实例使用的 Java 版本是否符合游戏与模组要求。"},
        @{@"match":@"Mod resolution encountered an incompatible mod set",@"kind":@"mod-dependency",@"title":@"可能原因：模组依赖或版本冲突",@"hint":@"根据原始日志检查缺失依赖、Minecraft 版本及加载器；不要仅凭文件名判断兼容性。"},
        @{@"match":@"UnsatisfiedLinkError",@"kind":@"native-library",@"title":@"可能原因：原生库加载失败",@"hint":@"检查日志中的库名。桌面系统的原生库不能直接用于 iOS。"},
        @{@"match":@"VK_ERROR_DEVICE_LOST",@"kind":@"graphics",@"title":@"可能原因：图形设备或渲染失败",@"hint":@"保留原始日志并反馈，勿盲目删除存档或重装全部文件。"}
    ];
    for (NSDictionary *rule in rules) if ([log rangeOfString:rule[@"match"] options:NSCaseInsensitiveSearch].location!=NSNotFound) return rule;
    return @{@"kind":@"unknown",@"title":@"暂未识别具体原因",@"hint":@"请查看原始日志，并通过 Issue 或邮件附上日志与复现步骤。"};
}
@end
