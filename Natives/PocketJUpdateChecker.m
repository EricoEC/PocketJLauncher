#import "PocketJUpdateChecker.h"

NSNotificationName const PocketJUpdateAvailabilityDidChangeNotification =
    @"PocketJUpdateAvailabilityDidChangeNotification";
static NSString *const PocketJDismissedReleaseKey = @"PocketJDismissedReleaseTag";

@interface PocketJUpdateChecker ()
@property(nonatomic, readwrite) NSDictionary *availableRelease;
@end


@implementation PocketJUpdateChecker

+ (instancetype)shared {
    static PocketJUpdateChecker *checker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ checker = [PocketJUpdateChecker new]; });
    return checker;
}

- (void)checkForUpdates {
    [self checkForUpdatesWithCompletion:nil];
}

- (void)checkForUpdatesWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:
        @"https://api.github.com/repos/EricoEC/PocketJLauncher/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 12;
    [request setValue:@"PocketJLauncher-iOS" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
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
        NSString *latest = ([[tag lowercaseString] hasPrefix:@"v"] && tag.length > 1)
            ? [tag substringFromIndex:1] : tag;
        NSString *current = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
        NSString *dismissed = [NSUserDefaults.standardUserDefaults stringForKey:PocketJDismissedReleaseKey];
        BOOL newer = [current compare:latest options:NSNumericSearch] == NSOrderedAscending;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.availableRelease = newer && ![dismissed isEqualToString:tag] ? release : nil;
            [NSNotificationCenter.defaultCenter
                postNotificationName:PocketJUpdateAvailabilityDidChangeNotification object:self];
            if (completion) completion(newer ? release : nil, nil);
        });
    }] resume];
}

- (void)dismissAvailableRelease {
    NSString *tag = self.availableRelease[@"tag_name"];
    if (tag.length) [NSUserDefaults.standardUserDefaults setObject:tag forKey:PocketJDismissedReleaseKey];
    self.availableRelease = nil;
    [NSNotificationCenter.defaultCenter
        postNotificationName:PocketJUpdateAvailabilityDidChangeNotification object:self];
}

@end
