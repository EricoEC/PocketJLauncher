#import "PocketJUpdatePrompt.h"
#import "PocketJUpdateChecker.h"
#import "utils.h"

@interface PocketJUpdatePrompt ()
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, weak) UIAlertController *visibleAlert;
@property(nonatomic) NSDictionary *pendingRelease;
@property(nonatomic) BOOL manual;
@property(nonatomic) BOOL channels;
@property(nonatomic) NSTimer *retryTimer;
@end

@implementation PocketJUpdatePrompt
+ (instancetype)shared {
    static PocketJUpdatePrompt *prompt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ prompt = [PocketJUpdatePrompt new]; });
    return prompt;
}
+ (void)showRelease:(NSDictionary *)release from:(UIViewController *)controller manual:(BOOL)manual {
    PocketJUpdatePrompt *prompt = self.shared;
    if (!release || (!manual && prompt.pendingRelease && prompt.manual)) return;
    // A manual check while this dialog is visible already has a visible result.
    if (prompt.visibleAlert.presentingViewController && !prompt.pendingRelease) return;
    prompt.host = controller;
    prompt.pendingRelease = release;
    prompt.manual = manual;
    prompt.channels = NO;
    [prompt schedulePresentation];
}
- (void)schedulePresentation {
    if (!self.retryTimer) {
        __weak typeof(self) weakSelf = self;
        self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES
            block:^(NSTimer *timer) { [weakSelf attemptPresentation]; }];
        [NSRunLoop.mainRunLoop addTimer:self.retryTimer forMode:NSRunLoopCommonModes];
    }
    [self attemptPresentation];
}
- (void)clearPending {
    self.pendingRelease = nil;
    [self.retryTimer invalidate];
    self.retryTimer = nil;
}
- (void)attemptPresentation {
    UIViewController *host = self.host;
    if (!host || !self.pendingRelease) { [self clearPending]; return; }
    if (!host.viewIfLoaded.window) { [self clearPending]; return; }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (self.visibleAlert.presentingViewController) return;
    UIViewController *presenter = host;
    while (presenter.presentedViewController) {
        if ([presenter.presentedViewController isKindOfClass:UIAlertController.class] ||
            presenter.presentedViewController.isBeingDismissed) return;
        presenter = presenter.presentedViewController;
    }
    if (presenter.isBeingDismissed || presenter.isBeingPresented) return;
    NSDictionary *release = self.pendingRelease;
    if (!self.channels && ![PocketJUpdateChecker.shared shouldPromptForRelease:release manual:self.manual]) {
        [self clearPending]; return;
    }
    BOOL channels = self.channels;
    [self clearPending];
    UIAlertController *alert;
    if (channels) {
        alert = [UIAlertController alertControllerWithTitle:localize(@"选择下载来源", nil)
            message:release[@"tag_name"] preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *sources = @[
            @[@"GitHub Releases", @"https://github.com/EricoEC/PocketJLauncher/releases"],
            @[localize(@"123 云盘", nil), @"https://1842976282.share.123pan.cn/123pan/5B6UTd-KLi1A"]
        ];
        for (NSArray *source in sources) {
            [alert addAction:[UIAlertAction actionWithTitle:source[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [UIApplication.sharedApplication openURL:[NSURL URLWithString:source[1]] options:@{} completionHandler:nil];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
        alert.popoverPresentationController.sourceView = presenter.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    } else {
        alert = [UIAlertController alertControllerWithTitle:localize(@"发现新版本", nil)
            message:[NSString stringWithFormat:localize(@"PocketJ Launcher %@ 已发布，是否前往更新？", nil), release[@"tag_name"] ?: @""]
            preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *update = [UIAlertAction actionWithTitle:localize(@"立即更新", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.pendingRelease = release;
            self.channels = YES;
            [self schedulePresentation]; // Wait for the first alert to actually dismiss.
        }];
        [alert addAction:update];
        alert.preferredAction = update;
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"下次再说", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [PocketJUpdateChecker.shared remindLaterForRelease:release];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"跳过此版本", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [PocketJUpdateChecker.shared skipRelease:release];
        }]];
    }
    self.visibleAlert = alert;
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end
