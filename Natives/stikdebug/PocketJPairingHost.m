#import "PocketJPairingHost.h"
#import "StikDebugEngine.h"
#import "../utils.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>
#import <dlfcn.h>

NSNotificationName const PocketJPairingHostDidChangeNotification = @"PocketJPairingHostDidChange";
static NSString *const PINNotification = @"PocketJPairingPIN";
static NSString *const CompletionNotification = @"PocketJPairingComplete";
typedef void (*PairEvent)(void *, int32_t, const char *);
typedef void *(*PairNew)(void);
typedef void (*PairRun)(void *, PairEvent, void *);
typedef void (*PairCancel)(void *);
typedef void (*PairFree)(void *);

@interface PocketJPairingHost () <NSNetServiceDelegate, NSNetServiceBrowserDelegate>
@property(nonatomic) BOOL running;
@property(nonatomic) PocketJPairingState state;
@property(nonatomic) BOOL successFeedbackPending;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSString *PIN;
@property(nonatomic, strong) NSNetService *service;
@property(nonatomic, strong) NSNetServiceBrowser *browser;
@property(nonatomic, strong) AVAudioPlayer *keepAlive;
@property(nonatomic, copy) NSString *oldAudioCategory;
@property(nonatomic, copy) NSString *oldAudioMode;
@property(nonatomic) AVAudioSessionCategoryOptions oldAudioOptions;
@property(nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@property(nonatomic) void *library;
@property(nonatomic) void *session;
@property(nonatomic) PairRun runFunction;
@property(nonatomic) PairCancel cancelFunction;
@property(nonatomic) PairFree freeFunction;
@property(nonatomic) BOOL cancelling;
@property(nonatomic) BOOL terminalReceived;
- (void)receiveEvent:(int32_t)kind text:(NSString *)text;
@end

static void PairingEvent(void *context, int32_t kind, const char *payload) {
    // The Rust buffer is borrowed; copy before leaving this callback.
    NSString *text = payload ? [NSString stringWithUTF8String:payload] : @"";
    PocketJPairingHost *host = (__bridge PocketJPairingHost *)context;
    dispatch_async(dispatch_get_main_queue(), ^{ [host receiveEvent:kind text:text ?: @""]; });
}

@implementation PocketJPairingHost
+ (instancetype)sharedHost {
    static PocketJPairingHost *host;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        host = [self new];
        host.status = @"";
        host.backgroundTask = UIBackgroundTaskInvalid;
        [NSNotificationCenter.defaultCenter addObserver:host selector:@selector(applicationDidBecomeActive:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
    });
    return host;
}
+ (BOOL)isSupported {
    return [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){27, 0, 0}];
}
- (void)changed {
    [NSNotificationCenter.defaultCenter postNotificationName:PocketJPairingHostDidChangeNotification object:self];
}
- (void)start {
    NSAssert(NSThread.isMainThread, @"Pairing is owned by the main thread");
    if (self.running) return;
    if (!self.class.isSupported) {
        self.state = PocketJPairingStateFailed;
        self.status = localize(@"本机配对需要 iOS 27 或更高版本；当前系统请使用电脑生成并导入配对文件。", nil);
        [self changed];
        return;
    }
    if (!self.library) {
        NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"libpocketj_pairing.dylib"];
        self.library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    }
    PairNew create = self.library ? (PairNew)dlsym(self.library, "pocketj_pairing_new") : NULL;
    self.runFunction = self.library ? (PairRun)dlsym(self.library, "pocketj_pairing_run") : NULL;
    self.cancelFunction = self.library ? (PairCancel)dlsym(self.library, "pocketj_pairing_cancel") : NULL;
    self.freeFunction = self.library ? (PairFree)dlsym(self.library, "pocketj_pairing_free") : NULL;
    if (!create || !self.runFunction || !self.cancelFunction || !self.freeFunction) {
        self.state = PocketJPairingStateFailed;
        self.status = localize(@"本机配对组件未就绪，请使用电脑导入配对文件。", nil);
        [self changed];
        return;
    }
    self.session = create();
    if (!self.session) return;
    self.running = YES;
    self.state = PocketJPairingStateWorking;
    self.successFeedbackPending = NO;
    [UNUserNotificationCenter.currentNotificationCenter removePendingNotificationRequestsWithIdentifiers:@[CompletionNotification]];
    [UNUserNotificationCenter.currentNotificationCenter removeDeliveredNotificationsWithIdentifiers:@[CompletionNotification]];
    self.cancelling = NO;
    self.terminalReceived = NO;
    self.PIN = nil;
    self.status = localize(@"正在启动本机配对…请允许本地网络访问。", nil);
    [self changed];
    // A notification makes the PIN visible while Settings is frontmost. Denial
    // does not block pairing: the code remains visible in PocketJ's pairing page.
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:
        UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {}];
    [self beginKeepAlive];
    // Browsing explicitly triggers Local Network privacy before the user leaves
    // for Settings; publishing alone is not a reliable permission prompt.
    self.browser = [NSNetServiceBrowser new];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_remotepairing-pairable-host._tcp." inDomain:@"local."];
    void *session = self.session;
    PairRun run = self.runFunction;
    PairFree release = self.freeFunction;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        run(session, PairingEvent, (__bridge void *)self);
        // run has returned; cancellation can no longer race handle destruction.
        dispatch_async(dispatch_get_main_queue(), ^{
            release(session);
            self.session = NULL;
            if (!self.terminalReceived) self.status = self.cancelling
                ? localize(@"已取消本机配对，原配对文件未更改。", nil)
                : localize(@"本机配对已结束，请重试。", nil);
            if (!self.terminalReceived) self.state = self.cancelling ? PocketJPairingStateCancelled : PocketJPairingStateFailed;
            self.running = NO;
            self.PIN = nil;
            [self endKeepAlive];
            [self changed];
        });
    });
}
- (void)cancel {
    if (!self.running || !self.session) return;
    self.cancelling = YES;
    [self.service stop];
    self.service = nil;
    [self.browser stop];
    self.browser = nil;
    self.cancelFunction(self.session);
}
- (void)receiveEvent:(int32_t)kind text:(NSString *)text {
    if (!self.running || self.terminalReceived) return;
    if (self.cancelling && kind < 3) return;
    if (kind == 0) {
        NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSString *identifier = info[@"identifier"];
        int port = [info[@"port"] intValue];
        if (!identifier.length || port <= 0 || port > UINT16_MAX) { [self cancel]; return; }
        NSMutableDictionary *txt = [NSMutableDictionary dictionary];
        for (NSArray *pair in info[@"txt"]) {
            if (pair.count == 2) txt[pair[0]] = [pair[1] dataUsingEncoding:NSUTF8StringEncoding];
        }
        self.service = [[NSNetService alloc] initWithDomain:@"local."
            type:@"_remotepairing-pairable-host._tcp." name:identifier port:port];
        self.service.delegate = self;
        [self.service setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]];
        [self.service publish];
        self.status = localize(@"打开系统设置 → 隐私与安全性 → 开发者模式，选择“与 PocketJ Launcher 配对”。需开启 Wi-Fi 和开发者模式。", nil);
    } else if (kind == 1) {
        if (text.length != 6 || [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return;
        self.PIN = text;
        self.status = localize(@"将配对码输入系统设置；配对完成后返回 PocketJ。", nil);
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = localize(@"PocketJ 本机配对码", nil);
        content.body = text;
        [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:
            [UNNotificationRequest requestWithIdentifier:PINNotification content:content trigger:nil]
            withCompletionHandler:nil];
    } else {
        self.terminalReceived = YES;
        if (self.cancelling || kind == 4) {
            self.state = PocketJPairingStateCancelled;
            self.status = localize(@"已取消本机配对，原配对文件未更改。", nil);
        } else if (kind == 2) {
            NSError *error = nil;
            BOOL saved = [StikDebugEngine.sharedEngine saveGeneratedPairingData:
                [text dataUsingEncoding:NSUTF8StringEncoding] error:&error];
            self.state = saved ? PocketJPairingStateSucceeded : PocketJPairingStateFailed;
            self.status = saved
                ? localize(@"本机配对文件已保存。开启 LocalDevVPN 后，可使用原有“开启 JIT”按钮。", nil)
                : (error ? localize(error.localizedDescription, nil) : localize(@"配对文件保存失败。", nil));
            if (saved) {
                self.successFeedbackPending = YES;
                if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
                    [self deliverSuccessFeedback];
                } else {
                    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
                    content.title = localize(@"配对成功", nil);
                    content.body = localize(@"配对文件已保存，返回 PocketJ 继续开启 JIT。", nil);
                    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:
                        [UNNotificationRequest requestWithIdentifier:CompletionNotification content:content trigger:nil]
                        withCompletionHandler:nil];
                }
            }
        } else {
            self.state = PocketJPairingStateFailed;
            // Never include protocol contents or credentials in logs/UI errors.
            self.status = [text isEqualToString:@"Pairing timed out"]
                ? localize(@"本机配对超时，请检查本地网络权限、Wi-Fi 和开发者模式后重试。原配对文件未更改。", nil)
                : localize(@"本机配对失败，请重新开始，并确认系统设置中的配对码。原配对文件未更改。", nil);
        }
    }
    [self changed];
}
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    if (!self.running || self.terminalReceived || sender != self.service) return;
    [self cancel];
    // Preserve this more actionable failure instead of the cancellation text.
    self.status = localize(@"无法发布配对服务，请在系统设置中允许 PocketJ 访问本地网络后重试。", nil);
    self.state = PocketJPairingStateFailed;
    self.terminalReceived = YES;
    [self changed];
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    if (browser == self.browser) [self netService:self.service didNotPublish:errorDict];
}
- (void)applicationDidBecomeActive:(NSNotification *)note {
    [self deliverSuccessFeedback];
    [self changed];
}
- (void)deliverSuccessFeedback {
    if (!self.successFeedbackPending || self.state != PocketJPairingStateSucceeded) return;
    self.successFeedbackPending = NO;
    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, localize(@"配对成功", nil));
}
- (void)beginKeepAlive {
    self.backgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{ [self cancel]; }];
    // Bounded silent playback keeps the listener alive during the Settings PIN
    // flow. It is stopped on every terminal path, never used outside pairing.
    AVAudioSession *audio = AVAudioSession.sharedInstance;
    self.oldAudioCategory = audio.category;
    self.oldAudioMode = audio.mode;
    self.oldAudioOptions = audio.categoryOptions;
    if (![audio setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil] ||
        ![audio setActive:YES error:nil]) return;
    uint32_t samples = 8000, length = samples * 2, size = length + 36, rate = 8000, byteRate = 16000;
    uint16_t format = 1, channels = 1, alignment = 2, bits = 16;
    NSMutableData *wav = [NSMutableData data];
    [wav appendBytes:"RIFF" length:4]; [wav appendBytes:&size length:4];
    [wav appendBytes:"WAVEfmt " length:8]; uint32_t fmtSize = 16;
    [wav appendBytes:&fmtSize length:4]; [wav appendBytes:&format length:2];
    [wav appendBytes:&channels length:2]; [wav appendBytes:&rate length:4];
    [wav appendBytes:&byteRate length:4]; [wav appendBytes:&alignment length:2];
    [wav appendBytes:&bits length:2]; [wav appendBytes:"data" length:4];
    [wav appendBytes:&length length:4]; [wav increaseLengthBy:length];
    self.keepAlive = [[AVAudioPlayer alloc] initWithData:wav error:nil];
    self.keepAlive.numberOfLoops = -1;
    [self.keepAlive play];
}
- (void)endKeepAlive {
    [self.service stop]; self.service = nil;
    [self.browser stop]; self.browser = nil;
    [self.keepAlive stop]; self.keepAlive = nil;
    if (self.oldAudioCategory) {
        [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        [AVAudioSession.sharedInstance setCategory:self.oldAudioCategory mode:self.oldAudioMode options:self.oldAudioOptions error:nil];
        self.oldAudioCategory = nil;
    }
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
    [UNUserNotificationCenter.currentNotificationCenter removePendingNotificationRequestsWithIdentifiers:@[PINNotification]];
    [UNUserNotificationCenter.currentNotificationCenter removeDeliveredNotificationsWithIdentifiers:@[PINNotification]];
}
@end
