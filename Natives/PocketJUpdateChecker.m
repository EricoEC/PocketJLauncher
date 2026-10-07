#import "PocketJUpdateChecker.h"

NSNotificationName const PocketJUpdateAvailabilityDidChangeNotification =
    @"PocketJUpdateAvailabilityDidChangeNotification";
static NSString *const PocketJCachedReleaseKey = @"PocketJCachedRelease";
static NSString *const PocketJLastKnownUpdateStateKey = @"PocketJLastKnownUpdateState";
static NSString *const PocketJLastCheckedAppVersionKey = @"PocketJLastCheckedAppVersion";
static NSString *const PocketJUpdateStateAvailable = @"available";
static NSString *const PocketJUpdateStateCurrent = @"current";

@interface PocketJUpdateChecker ()
@property(nonatomic, readwrite) NSDictionary *availableRelease;
@property(nonatomic) BOOL dismissedForCurrentSession;
@end


@implementation PocketJUpdateChecker

+ (instancetype)shared {
    static PocketJUpdateChecker *checker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ checker = [PocketJUpdateChecker new]; });
    return checker;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *cached = [defaults dictionaryForKey:PocketJCachedReleaseKey];
    NSString *cachedTag = [cached[@"tag_name"] isKindOfClass:NSString.class]
        ? cached[@"tag_name"] : nil;
    if (cachedTag.length && [self isTagNewerThanCurrentVersion:cachedTag]) {
        _availableRelease = cached;
    } else if (cached) {
        [defaults removeObjectForKey:PocketJCachedReleaseKey];
        [defaults setObject:PocketJUpdateStateCurrent forKey:PocketJLastKnownUpdateStateKey];
    }
    return self;
}

- (NSString *)currentVersion {
    return NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
}

- (BOOL)isTagNewerThanCurrentVersion:(NSString *)tag {
    NSString *latest = ([[tag lowercaseString] hasPrefix:@"v"] && tag.length > 1)
        ? [tag substringFromIndex:1] : tag;
    return [[self currentVersion] compare:latest options:NSNumericSearch] == NSOrderedAscending;
}

- (NSDictionary *)cacheableReleaseFromRelease:(NSDictionary *)release {
    NSMutableDictionary *cached = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"tag_name", @"html_url", @"name", @"published_at"]) {
        id value = release[key];
        if ([value isKindOfClass:NSString.class]) cached[key] = value;
    }
    return cached;
}

- (void)checkForUpdates {
    [self performCheckIsManual:NO completion:nil];
}

- (void)checkForUpdatesWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    [self performCheckIsManual:YES completion:completion];
}

- (void)performCheckIsManual:(BOOL)isManual
                  completion:(void (^)(NSDictionary *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:
        @"https://api.github.com/repos/EricoEC/PocketJLauncher/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:url
           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
       timeoutInterval:12];
    [request setValue:@"PocketJLauncher-iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (error || !data.length || statusCode != 200) {
            NSError *resultError = error ?: [NSError errorWithDomain:@"PocketJUpdateChecker"
                code:statusCode userInfo:@{NSLocalizedDescriptionKey: @"Update request failed"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, resultError); });
            return;
        }
        NSError *JSONError;
        NSDictionary *release = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
        if (![release isKindOfClass:NSDictionary.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, JSONError); });
            return;
        }
        NSString *tag = release[@"tag_name"];
        if (!tag.length) {
            NSError *tagError = [NSError errorWithDomain:@"PocketJUpdateChecker" code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"Release tag is missing"}];
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, tagError); });
            return;
        }
        BOOL newer = [self isTagNewerThanCurrentVersion:tag];
        NSDictionary *cachedRelease = [self cacheableReleaseFromRelease:release];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            [defaults setObject:[self currentVersion] forKey:PocketJLastCheckedAppVersionKey];
            if (newer) {
                [defaults setObject:cachedRelease forKey:PocketJCachedReleaseKey];
                [defaults setObject:PocketJUpdateStateAvailable forKey:PocketJLastKnownUpdateStateKey];
                if (isManual) self.dismissedForCurrentSession = NO;
                self.availableRelease = self.dismissedForCurrentSession ? nil : cachedRelease;
            } else {
                [defaults removeObjectForKey:PocketJCachedReleaseKey];
                [defaults setObject:PocketJUpdateStateCurrent forKey:PocketJLastKnownUpdateStateKey];
                self.dismissedForCurrentSession = NO;
                self.availableRelease = nil;
            }
            [NSNotificationCenter.defaultCenter
                postNotificationName:PocketJUpdateAvailabilityDidChangeNotification object:self];
            if (completion) completion(newer ? cachedRelease : nil, nil);
        });
    }] resume];
}

- (void)dismissAvailableRelease {
    self.dismissedForCurrentSession = YES;
    self.availableRelease = nil;
    [NSNotificationCenter.defaultCenter
        postNotificationName:PocketJUpdateAvailabilityDidChangeNotification object:self];
}

@end
