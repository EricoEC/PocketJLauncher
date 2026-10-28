#import "PocketJDownloadClient.h"
#include <CommonCrypto/CommonDigest.h>

static NSError *PJDownloadError(NSInteger code, NSString *text) {
    return [NSError errorWithDomain:@"PocketJ.Download" code:code userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(text,nil)}];
}
@interface PJDownloadJob : NSObject <NSURLSessionDownloadDelegate>
@property(nonatomic) NSDictionary *descriptor;
@property(nonatomic) NSString *identifier;
@property(nonatomic) NSString *directory;
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionDownloadTask *task;
@property(nonatomic, copy) PJDownloadCompletion completion;
@property(nonatomic, copy) void (^progress)(double);
@property(nonatomic) NSUInteger attempt;
@property(nonatomic) BOOL stopped;
@property(nonatomic) BOOL finished;
@property(nonatomic, copy) void (^cleanup)(void);
- (void)start;
- (void)finish:(NSURL *)file error:(NSError *)error;
@end
@interface PocketJDownloadClient ()
@property(nonatomic) NSMutableDictionary<NSString *, PJDownloadJob *> *jobs;
@end
@implementation PocketJDownloadClient
+ (instancetype)shared { static id shared; static dispatch_once_t once; dispatch_once(&once, ^{ shared = [self new]; }); return shared; }
- (instancetype)init { if ((self = [super init])) _jobs = [NSMutableDictionary dictionary]; return self; }
- (NSString *)download:(NSDictionary *)descriptor instanceID:(NSString *)identity progress:(void (^)(double))progress completion:(PJDownloadCompletion)completion {
    // Content identity, not the instance's editable name, owns restart/resume data.
    NSString *input = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@", identity, descriptor[@"url"], descriptor[@"filename"], descriptor[@"hashes"][@"sha512"] ?: @"", descriptor[@"hashes"][@"sha256"] ?: @"", descriptor[@"hashes"][@"sha1"] ?: @""];
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *taskID = [NSMutableString string]; for (NSUInteger i=0;i<sizeof(digest);i++) [taskID appendFormat:@"%02x",digest[i]];
    @synchronized (self) {
        if (self.jobs[taskID]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, PJDownloadError(409, @"This download is already running.")); }); return taskID;
        }
        PJDownloadJob *job = [PJDownloadJob new]; job.identifier = taskID; job.descriptor = descriptor;
        NSString *root = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        job.directory = [[root stringByAppendingPathComponent:@"PocketJDownloads"] stringByAppendingPathComponent:taskID];
        job.progress = progress; job.completion = completion;
        __weak typeof(self) weakSelf = self;
        job.cleanup = ^{ @synchronized (weakSelf) { [weakSelf.jobs removeObjectForKey:taskID]; } };
        self.jobs[taskID] = job;
        [NSFileManager.defaultManager createDirectoryAtPath:job.directory withIntermediateDirectories:YES attributes:nil error:nil];
        // A descriptor can rebuild a request after process termination; opaque
        // NSURLSession resume data is an optional optimization, not the identity.
        [descriptor writeToFile:[job.directory stringByAppendingPathComponent:@"request.plist"] atomically:YES];
        [job start];
    }
    return taskID;
}
- (void)pause:(NSString *)taskID {
    @synchronized (self) {
        PJDownloadJob *job = self.jobs[taskID]; if (!job) return; job.stopped = YES;
        [job.task cancelByProducingResumeData:^(NSData *resumeData) {
            if (resumeData) [resumeData writeToFile:[job.directory stringByAppendingPathComponent:@"resume.data"] atomically:YES];
            [job finish:nil error:PJDownloadError(NSURLErrorCancelled, @"Download paused. Retry to resume.")];
        }];
    }
}
- (void)cancel:(NSString *)taskID {
    @synchronized (self) {
        PJDownloadJob *job = self.jobs[taskID]; if (!job) return; job.stopped = YES; [job.task cancel];
        [NSFileManager.defaultManager removeItemAtPath:job.directory error:nil];
        [job finish:nil error:PJDownloadError(NSURLErrorCancelled, @"Download cancelled.")];
    }
}
+ (BOOL)verifyFile:(NSURL *)file descriptor:(NSDictionary *)descriptor error:(NSError **)error {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:error];
    if (!attributes) return NO;
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    if (!size || ([descriptor[@"size"] unsignedLongLongValue] && size != [descriptor[@"size"] unsignedLongLongValue])) {
        if (error) *error = PJDownloadError(422, @"Downloaded file size does not match."); return NO;
    }
    NSDictionary *hashes = descriptor[@"hashes"];
    NSString *algorithm = [hashes[@"sha512"] length] ? @"sha512" : ([hashes[@"sha256"] length] ? @"sha256" : ([hashes[@"sha1"] length] ? @"sha1" : nil));
    if (algorithm) {
        CC_SHA1_CTX sha1; CC_SHA256_CTX sha256; CC_SHA512_CTX sha512; CC_SHA1_Init(&sha1); CC_SHA256_Init(&sha256); CC_SHA512_Init(&sha512);
        NSInputStream *stream = [NSInputStream inputStreamWithURL:file]; [stream open];
        uint8_t buffer[65536]; NSInteger n;
        while ((n = [stream read:buffer maxLength:sizeof(buffer)]) > 0) { CC_SHA1_Update(&sha1, buffer, (CC_LONG)n); CC_SHA256_Update(&sha256, buffer, (CC_LONG)n); CC_SHA512_Update(&sha512, buffer, (CC_LONG)n); }
        [stream close];
        if (n < 0 || stream.streamError) { if (error) *error = stream.streamError; return NO; }
        unsigned char digest[CC_SHA512_DIGEST_LENGTH];
        NSUInteger digestLength;
        if ([algorithm isEqual:@"sha512"]) { CC_SHA512_Final(digest, &sha512); digestLength=CC_SHA512_DIGEST_LENGTH; }
        else if ([algorithm isEqual:@"sha256"]) { CC_SHA256_Final(digest,&sha256); digestLength=CC_SHA256_DIGEST_LENGTH; }
        else { CC_SHA1_Final(digest, &sha1); digestLength=CC_SHA1_DIGEST_LENGTH; }
        NSMutableString *hex = [NSMutableString string]; for (NSUInteger i=0;i<digestLength;i++) [hex appendFormat:@"%02x",digest[i]];
        if (![hex isEqualToString:[hashes[algorithm] lowercaseString]]) { if (error) *error = PJDownloadError(422, @"Downloaded file hash does not match."); return NO; }
    }
    // Reject HTML/error pages masquerading as jar/zip; callers validate archive structure too.
    if ([descriptor[@"archive"] boolValue]) {
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:file error:error];
        NSData *prefix = [handle readDataOfLength:4]; [handle closeFile];
        const uint8_t *bytes = prefix.bytes;
        if (prefix.length != 4 || bytes[0] != 'P' || bytes[1] != 'K' ||
            !((bytes[2]==3 && bytes[3]==4) || (bytes[2]==5 && bytes[3]==6))) {
            if (error) *error = PJDownloadError(422, @"The server did not return a valid archive."); return NO;
        }
    }
    return YES;
}
@end

@implementation PJDownloadJob
- (void)start {
    if (self.stopped || self.finished) return;
    NSArray *candidates = self.descriptor[@"urls"] ?: @[self.descriptor[@"url"] ?: @""];
    NSString *string = candidates[self.attempt % MAX(candidates.count, 1)];
    NSURL *URL = [NSURL URLWithString:string];
    if (![URL.scheme.lowercaseString isEqual:@"https"] || !URL.host.length) {
        [self finish:nil error:PJDownloadError(400, @"A valid HTTPS download URL is required.")]; return;
    }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 600;
    config.HTTPAdditionalHeaders = @{@"User-Agent":@"PocketJLauncher/1.5 (Erico; add-on downloads)"};
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    NSData *resumeData = [NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:@"resume.data"]];
    self.task = resumeData.length && self.attempt == 0 ? [self.session downloadTaskWithResumeData:resumeData] : [self.session downloadTaskWithURL:URL];
    [self.task resume];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytes totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    if (!self.progress) return;
    double fraction = expected > 0 ? MIN(1, (double)written / expected) : 0;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.finished) self.progress(fraction); });
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    if (self.stopped || self.finished) return;
    NSInteger status = [(NSHTTPURLResponse *)task.response statusCode]; NSError *error;
    if (status < 200 || status >= 300) {
        [self retry:PJDownloadError(status, [NSString stringWithFormat:NSLocalizedString(@"Download server returned HTTP %ld.",nil), (long)status])]; return;
    }
    if (![PocketJDownloadClient verifyFile:location descriptor:self.descriptor error:&error]) { [self retry:error]; return; }
    NSURL *target = [NSURL fileURLWithPath:[self.directory stringByAppendingPathComponent:@"verified.part"]];
    [NSFileManager.defaultManager removeItemAtURL:target error:nil];
    if (![NSFileManager.defaultManager moveItemAtURL:location toURL:target error:&error]) { [self finish:nil error:error]; return; }
    [NSFileManager.defaultManager removeItemAtPath:[self.directory stringByAppendingPathComponent:@"resume.data"] error:nil];
    [self finish:target error:nil];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error || self.finished || self.stopped || session != self.session) return;
    NSData *resume = error.userInfo[NSURLSessionDownloadTaskResumeData];
    if (resume) [resume writeToFile:[self.directory stringByAppendingPathComponent:@"resume.data"] atomically:YES];
    [self retry:error];
}
- (void)retry:(NSError *)error {
    if (self.stopped || self.finished) return;
    // Retry transient HTTP/transport failures and corrupt downloads, not permission/not-found errors.
    if (self.attempt >= 2 || error.code == 403 || error.code == 404) { [self finish:nil error:error]; return; }
    [self.session invalidateAndCancel]; self.session = nil;
    NSTimeInterval delay = 1 << self.attempt; self.attempt++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self start]; });
}
- (void)finish:(NSURL *)file error:(NSError *)error {
    @synchronized (self) {
        if (self.finished) return; self.finished = YES;
        [self.session finishTasksAndInvalidate]; self.session = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ self.completion(file, error); if (self.cleanup) self.cleanup(); });
    }
}
@end
