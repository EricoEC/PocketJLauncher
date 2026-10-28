#import "PocketJUpdateChecker.h"

NSNotificationName const PocketJUpdateAvailabilityDidChangeNotification = @"PocketJUpdateAvailabilityDidChangeNotification";
static NSString *const PocketJCachedReleaseKey = @"PocketJCachedRelease";
static NSString *const PocketJLastKnownUpdateStateKey = @"PocketJLastKnownUpdateState";
static NSString *const PocketJLastCheckedAppVersionKey = @"PocketJLastCheckedAppVersion";
static NSString *const PocketJSkippedVersionKey = @"PocketJSkippedUpdateVersion";
static NSString *const PocketJDeferredVersionKey = @"PocketJDeferredUpdateVersion";
static NSString *const PocketJRemindAfterKey = @"PocketJUpdateRemindAfter";

@interface PocketJUpdateChecker ()
@property(nonatomic, readwrite) NSDictionary *availableRelease;
@property(nonatomic) BOOL dismissedForCurrentSession;
@property(nonatomic) NSUserDefaults *defaults;
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSString *installedVersion;
@property(nonatomic) BOOL checking;
@property(nonatomic) BOOL manualRequestPending;
@property(nonatomic) NSMutableArray *completions;
@end

@implementation PocketJUpdateChecker
+ (instancetype)shared {
    static PocketJUpdateChecker *checker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ checker = [PocketJUpdateChecker new]; });
    return checker;
}
- (instancetype)init {
    return [self initWithDefaults:NSUserDefaults.standardUserDefaults session:NSURLSession.sharedSession
        currentVersion:NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0"];
}
// Injectable dependencies keep network/cache/prompt policy regression-testable.
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults session:(NSURLSession *)session
                 currentVersion:(NSString *)version {
    self = [super init];
    if (!self) return nil;
    _defaults = defaults;
    _session = session;
    _installedVersion = version;
    _completions = [NSMutableArray new];
    NSDictionary *cached = [defaults dictionaryForKey:PocketJCachedReleaseKey];
    if ([self isTagNewerThanCurrentVersion:cached[@"tag_name"]]) _availableRelease = cached;
    else if (cached) {
        [defaults removeObjectForKey:PocketJCachedReleaseKey];
        [defaults setObject:@"current" forKey:PocketJLastKnownUpdateStateKey];
    }
    return self;
}
+ (NSString *)normalizedVersion:(id)tag {
    if (![tag isKindOfClass:NSString.class]) return nil;
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"^[vV]?[0-9]{1,9}(?:\\.[0-9]{1,9}){1,3}$" options:0 error:nil];
    });
    NSTextCheckingResult *match = [pattern firstMatchInString:tag options:0 range:NSMakeRange(0, [tag length])];
    if (!match || match.range.length != [tag length]) return nil;
    NSString *text = [tag hasPrefix:@"v"] || [tag hasPrefix:@"V"] ? [tag substringFromIndex:1] : tag;
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *part in [text componentsSeparatedByString:@"."]) [parts addObject:@(part.integerValue).stringValue];
    while (parts.count > 1 && [parts.lastObject isEqual:@"0"]) [parts removeLastObject];
    return [parts componentsJoinedByString:@"."];
}
- (BOOL)isTagNewerThanCurrentVersion:(id)tag {
    NSString *latest = [self.class normalizedVersion:tag];
    if (!latest) return NO;
    NSString *current = [self.class normalizedVersion:self.installedVersion] ?: self.installedVersion;
    return [current compare:latest options:NSNumericSearch] == NSOrderedAscending;
}
+ (NSDictionary *)newestLauncherRelease:(NSArray *)releases {
    NSDictionary *best = nil;
    NSString *bestVersion = nil;
    for (id candidate in releases) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        id draft = candidate[@"draft"], prerelease = candidate[@"prerelease"];
        if (![draft isKindOfClass:NSNumber.class] || ![prerelease isKindOfClass:NSNumber.class] ||
            [draft boolValue] || [prerelease boolValue]) continue;
        NSString *version = [self normalizedVersion:candidate[@"tag_name"]];
        if (version && (!bestVersion || [bestVersion compare:version options:NSNumericSearch] == NSOrderedAscending)) {
            best = candidate;
            bestVersion = version;
        }
    }
    return best;
}
- (NSDictionary *)cacheableReleaseFromRelease:(NSDictionary *)release {
    NSMutableDictionary *cached = [NSMutableDictionary new];
    for (NSString *key in @[@"tag_name", @"html_url", @"name", @"published_at"]) {
        id value = release[key];
        if ([value isKindOfClass:NSString.class]) cached[key] = value;
    }
    return cached;
}
- (void)checkForUpdates { [self performCheckIsManual:NO completion:nil]; }
- (void)checkForUpdatesWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    [self performCheckIsManual:YES completion:completion];
}
- (void)performCheckIsManual:(BOOL)manual completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self performCheckIsManual:manual completion:completion]; });
        return;
    }
    self.manualRequestPending |= manual;
    if (completion) [self.completions addObject:[completion copy]];
    if (self.checking) return; // Join the actual in-flight request, never a cached manual answer.
    self.checking = YES;
    [self fetchPage:1 best:nil];
}
- (void)fetchPage:(NSUInteger)page best:(NSDictionary *)previous {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://api.github.com/repos/EricoEC/PocketJLauncher/releases?per_page=100&page=%lu", (unsigned long)page]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    [request setValue:@"PocketJLauncher-iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (error || status != 200 || !data.length) {
            [self finishWithRelease:nil error:error ?: [self requestError:status]];
            return;
        }
        id JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![JSON isKindOfClass:NSArray.class]) { [self finishWithRelease:nil error:[self requestError:-1]]; return; }
        NSDictionary *candidate = [self.class newestLauncherRelease:JSON];
        NSDictionary *best = [self.class newestLauncherRelease:
            previous ? (candidate ? @[previous, candidate] : @[previous]) : (candidate ? @[candidate] : @[])];
        // Walk full pages; a pairing-tool release cannot hide the newest launcher.
        if ([JSON count] == 100) {
            if (page >= 20) { [self finishWithRelease:nil error:[self requestError:-2]]; return; }
            [self fetchPage:page + 1 best:best];
        } else [self finishWithRelease:best error:nil];
    }] resume];
}
- (NSError *)requestError:(NSInteger)code {
    return [NSError errorWithDomain:@"PocketJUpdateChecker" code:code
        userInfo:@{NSLocalizedDescriptionKey: @"Update request failed"}];
}
- (void)finishWithRelease:(NSDictionary *)release error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL manual = self.manualRequestPending;
        BOOL newer = !error && [self isTagNewerThanCurrentVersion:release[@"tag_name"]];
        NSDictionary *cached = newer ? [self cacheableReleaseFromRelease:release] : nil;
        if (!error) {
            [self.defaults setObject:self.installedVersion forKey:PocketJLastCheckedAppVersionKey];
            [self.defaults setObject:newer ? @"available" : @"current" forKey:PocketJLastKnownUpdateStateKey];
            if (newer) [self.defaults setObject:cached forKey:PocketJCachedReleaseKey];
            else [self.defaults removeObjectForKey:PocketJCachedReleaseKey];
            if (manual || !newer) self.dismissedForCurrentSession = NO;
            self.availableRelease = self.dismissedForCurrentSession ? nil : cached;
        } // Offline/error: do not erase the last known release or status.
        NSArray *callbacks = self.completions.copy;
        [self.completions removeAllObjects];
        self.checking = NO;
        self.manualRequestPending = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:PocketJUpdateAvailabilityDidChangeNotification
            object:self userInfo:@{@"checkFinished": @YES, @"manual": @(manual)}];
        for (void (^callback)(NSDictionary *, NSError *) in callbacks) callback(cached, error);
    });
}
- (NSDate *)now { return NSDate.date; }
- (BOOL)shouldPromptForRelease:(NSDictionary *)release manual:(BOOL)manual {
    NSString *version = [self.class normalizedVersion:release[@"tag_name"]];
    if (!version || ![self isTagNewerThanCurrentVersion:release[@"tag_name"]]) return NO;
    if (manual) return YES;
    if ([version isEqual:[self.defaults stringForKey:PocketJSkippedVersionKey]]) return NO;
    NSDate *after = [self.defaults objectForKey:PocketJRemindAfterKey];
    return !([version isEqual:[self.defaults stringForKey:PocketJDeferredVersionKey]] &&
        [after isKindOfClass:NSDate.class] && [[self now] compare:after] == NSOrderedAscending);
}
- (void)remindLaterForRelease:(NSDictionary *)release {
    NSString *version = [self.class normalizedVersion:release[@"tag_name"]];
    if (!version) return;
    [self.defaults setObject:version forKey:PocketJDeferredVersionKey];
    [self.defaults setObject:[[self now] dateByAddingTimeInterval:3 * 60 * 60] forKey:PocketJRemindAfterKey];
}
- (void)skipRelease:(NSDictionary *)release {
    NSString *version = [self.class normalizedVersion:release[@"tag_name"]];
    if (version) [self.defaults setObject:version forKey:PocketJSkippedVersionKey];
}
- (void)dismissAvailableRelease {
    self.dismissedForCurrentSession = YES;
    self.availableRelease = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:PocketJUpdateAvailabilityDidChangeNotification object:self];
}
@end
