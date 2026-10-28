#import <Foundation/Foundation.h>
#import "PocketJUpdateChecker.h"
#include <assert.h>

@interface PocketJUpdateChecker (Tests)
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults session:(NSURLSession *)session currentVersion:(NSString *)version;
+ (NSString *)normalizedVersion:(id)tag;
+ (NSDictionary *)newestLauncherRelease:(NSArray *)releases;
- (NSDate *)now;
@end
static NSDate *testNow;
@interface ClockChecker : PocketJUpdateChecker @end
@implementation ClockChecker
- (NSDate *)now { return testNow; }
@end
@interface FakeTask : NSObject
@property(nonatomic, copy) void (^work)(void);
- (void)resume;
@end
@implementation FakeTask
- (void)resume { dispatch_async(dispatch_get_main_queue(), self.work); }
@end
@interface FakeSession : NSObject
@property(nonatomic) NSMutableArray *responses;
@property(nonatomic) NSUInteger requests;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end
@implementation FakeSession
- (instancetype)init { if ((self = [super init])) _responses = [NSMutableArray new]; return self; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    self.requests++;
    assert([request.URL.host isEqual:@"api.github.com"]);
    assert([request.URL.path isEqual:@"/repos/EricoEC/PocketJLauncher/releases"]);
    assert(request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData);
    assert(![request valueForHTTPHeaderField:@"Authorization"]);
    assert(self.responses.count);
    id response = self.responses.firstObject;
    [self.responses removeObjectAtIndex:0];
    FakeTask *task = [FakeTask new];
    task.work = ^{
        if ([response isKindOfClass:NSError.class]) { completion(nil, nil, response); return; }
        NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
        NSHTTPURLResponse *http = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        completion(data, http, nil);
    };
    return (NSURLSessionDataTask *)task;
}
@end
static NSDictionary *Release(NSString *tag) {
    return @{@"tag_name": tag, @"draft": @NO, @"prerelease": @NO,
        @"html_url": [@"https://github.com/EricoEC/PocketJLauncher/releases/tag/" stringByAppendingString:tag]};
}
static void Wait(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(done());
}
static void Check(ClockChecker *checker, BOOL expectError, NSString *expectedTag) {
    __block BOOL done = NO;
    [checker checkForUpdatesWithCompletion:^(NSDictionary *release, NSError *error) {
        assert(NSThread.isMainThread);
        assert((error != nil) == expectError);
        assert(expectedTag ? [release[@"tag_name"] isEqual:expectedTag] : release == nil);
        done = YES;
    }];
    Wait(^BOOL{ return done; });
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    testNow = [NSDate dateWithTimeIntervalSince1970:100000];
    NSString *suite = [@"PocketJUpdateTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    FakeSession *session = [FakeSession new];
    ClockChecker *checker = [[ClockChecker alloc] initWithDefaults:defaults session:(NSURLSession *)session currentVersion:@"1.5"];
    assert(!checker.availableRelease);
    assert(![PocketJUpdateChecker normalizedVersion:@"pairing-tool-v99.0"]);
    assert(![PocketJUpdateChecker normalizedVersion:@"v1.6-beta"]);
    assert(![PocketJUpdateChecker normalizedVersion:@"v1.6\n"]);
    assert(![PocketJUpdateChecker normalizedVersion:NSNull.null]);
    assert([[PocketJUpdateChecker normalizedVersion:@"V01.5.0"] isEqual:@"1.5"]);
    NSMutableDictionary *draft = [Release(@"v99.0") mutableCopy]; draft[@"draft"] = @YES;
    NSMutableDictionary *beta = [Release(@"v98.0") mutableCopy]; beta[@"prerelease"] = @YES;
    NSArray *mixed = @[Release(@"pairing-tool-v100.0"), draft, beta, Release(@"v1.9"), Release(@"v1.10")];
    assert([[PocketJUpdateChecker newestLauncherRelease:mixed][@"tag_name"] isEqual:@"v1.10"]);

    [session.responses addObject:@[Release(@"pairing-tool-v99.0"), Release(@"v1.6")]];
    Check(checker, NO, @"v1.6");
    assert([[defaults stringForKey:@"PocketJLastKnownUpdateState"] isEqual:@"available"]);
    NSDictionary *release = checker.availableRelease;
    assert([checker shouldPromptForRelease:release manual:NO]);
    [checker remindLaterForRelease:release];
    assert(![checker shouldPromptForRelease:release manual:NO]);
    assert([checker shouldPromptForRelease:release manual:YES]);
    testNow = [testNow dateByAddingTimeInterval:10799];
    assert(![checker shouldPromptForRelease:release manual:NO]);
    testNow = [testNow dateByAddingTimeInterval:1];
    assert([checker shouldPromptForRelease:release manual:NO]);
    [checker skipRelease:release];
    assert(![checker shouldPromptForRelease:release manual:NO]);
    assert([checker shouldPromptForRelease:release manual:YES]);
    assert([checker shouldPromptForRelease:Release(@"v1.7") manual:NO]);
    ClockChecker *reopened = [[ClockChecker alloc] initWithDefaults:defaults session:(NSURLSession *)session currentVersion:@"1.5"];
    assert([reopened.availableRelease[@"tag_name"] isEqual:@"v1.6"]);
    assert(![reopened shouldPromptForRelease:Release(@"V1.6.0") manual:NO]);
    assert([reopened shouldPromptForRelease:Release(@"V1.6.0") manual:YES]);

    NSError *offline = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    [session.responses addObject:offline];
    Check(reopened, YES, nil);
    assert([reopened.availableRelease[@"tag_name"] isEqual:@"v1.6"]);
    assert([[defaults stringForKey:@"PocketJLastKnownUpdateState"] isEqual:@"available"]);
    [session.responses addObject:@{@"unexpected": @YES}];
    Check(reopened, YES, nil);
    assert([reopened.availableRelease[@"tag_name"] isEqual:@"v1.6"]);

    // A manual request joins a real in-flight automatic request; both finish once.
    [session.responses addObject:@[Release(@"v1.7")]];
    NSUInteger before = session.requests;
    [reopened checkForUpdates];
    Check(reopened, NO, @"v1.7");
    assert(session.requests == before + 1);
    assert([reopened.availableRelease[@"tag_name"] isEqual:@"v1.7"]);

    // A full first page of tools cannot mask a launcher on the next page.
    NSMutableArray *tools = [NSMutableArray new];
    for (int i = 0; i < 100; i++) [tools addObject:Release(@"pairing-tool-v99.0")];
    [session.responses addObjectsFromArray:@[tools, @[Release(@"v1.8")]]];
    before = session.requests;
    Check(reopened, NO, @"v1.8");
    assert(session.requests == before + 2);
    [session.responses addObjectsFromArray:@[tools, offline]];
    Check(reopened, YES, nil);
    assert([reopened.availableRelease[@"tag_name"] isEqual:@"v1.8"]);

    [session.responses addObject:@[Release(@"v1.5.0"), Release(@"pairing-tool-v999.0")]];
    Check(reopened, NO, nil);
    assert(!reopened.availableRelease);
    assert([[defaults stringForKey:@"PocketJLastKnownUpdateState"] isEqual:@"current"]);
    [session.responses addObject:offline];
    Check(reopened, YES, nil);
    assert([[defaults stringForKey:@"PocketJLastKnownUpdateState"] isEqual:@"current"]);
    [defaults setObject:Release(@"pairing-tool-v99.0") forKey:@"PocketJCachedRelease"];
    ClockChecker *oldCache = [[ClockChecker alloc] initWithDefaults:defaults session:(NSURLSession *)session currentVersion:@"1.5"];
    assert(!oldCache.availableRelease && ![defaults objectForKey:@"PocketJCachedRelease"]);
    if (argc > 1 && !strcmp(argv[1], "--live")) {
        ClockChecker *live = [[ClockChecker alloc] initWithDefaults:defaults session:NSURLSession.sharedSession currentVersion:@"1.0"];
        __block BOOL done = NO;
        [live checkForUpdatesWithCompletion:^(NSDictionary *latest, NSError *error) {
            assert(!error && latest);
            assert([PocketJUpdateChecker normalizedVersion:latest[@"tag_name"]]);
            NSLog(@"PASS: unauthenticated live GitHub release selection: %@", latest[@"tag_name"]);
            done = YES;
        }];
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
        while (!done && limit.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        assert(done);
    }
    [defaults removePersistentDomainForName:suite];
    puts("PASS: release filtering/pagination, numeric versions, persistent cache, offline/schema failures, 3h cooldown, skip persistence, manual override and concurrent requests.");
} }
