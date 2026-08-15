#import <UIKit/UIKit.h>

@class ModpackAPI;

@interface MinecraftResourceDownloadTask : NSObject
@property NSProgress *progress, *textProgress;
@property NSMutableArray *fileList, *progressList;
@property NSMutableDictionary* metadata;
@property(nonatomic, copy) void(^handleError)(void);
/// Called after the original downloader has checked local metadata, client,
/// libraries and assets and knows whether any file must be downloaded.
@property(nonatomic, copy) void(^downloadPlanReady)(BOOL needsDownload);

- (NSURLSessionDownloadTask *)createDownloadTask:(NSString *)url size:(NSUInteger)size sha:(NSString *)sha altName:(NSString *)altName toPath:(NSString *)path;
- (void)finishDownloadWithErrorString:(NSString *)error;
- (void)cancel;
- (void)pause;
- (void)resume;

- (void)downloadVersion:(NSDictionary *)version;
- (void)downloadModpackFromAPI:(ModpackAPI *)api detail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion;

@end
