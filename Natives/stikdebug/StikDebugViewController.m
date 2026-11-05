#import "StikDebugViewController.h"
#import <dlfcn.h>
#import <unistd.h>
#import "StikDebugEngine.h"
#import "PocketJPairingFileViewController.h"
#import "PocketJPairingHost.h"
#import "../ModernUITheme.h"
#import "../UIKit+hook.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

@interface StikDebugViewController ()
@property(nonatomic) BOOL enabling;
@property(nonatomic) BOOL jitEnabled;
@property(nonatomic) BOOL vpnChecking;
@property(nonatomic) BOOL vpnConnected;
@property(nonatomic) BOOL vpnHasResult;
@property(nonatomic) BOOL visible;
@property(nonatomic) NSUInteger probeGeneration;
@property(nonatomic, strong) NSTimer *statusTimer;
@property(nonatomic, copy) NSString *lastStatus;
- (NSString *)userFacingErrorMessage:(NSString *)message;
@end
@protocol PocketJJITCoordinatorAPI <NSObject>
+ (void)enableJITWithTargetPID:(int32_t)targetPID pairingData:(NSData *)pairingData
    completion:(void (^)(BOOL success, NSString *message))completion;
@end
@implementation StikDebugViewController
+ (PocketJJITSetupState)setupState {
    if (@available(iOS 17.4, *)) {
        [StikDebugEngine.sharedEngine synchronizePairingFileFromDocuments:nil];
        if (isJITEnabled(YES)) return PocketJJITSetupStateEnabled;
        return StikDebugEngine.sharedEngine.hasPairingFile
            ? PocketJJITSetupStateReady
            : PocketJJITSetupStateWaitingConfiguration;
    }
    return PocketJJITSetupStateUnavailable;
}

+ (void)enableEmbeddedJITWithCompletion:
        (void (^)(BOOL success, NSString *message))completion {
    if (@available(iOS 26.0, *)) {
        NSData *pairingData = [NSData dataWithContentsOfFile:
            StikDebugEngine.sharedEngine.pairingFilePath];
        if (!pairingData.length) {
            if (completion) completion(NO, localize(@"请先导入本机配对文件。", nil));
            return;
        }
        NSString *framework = [NSBundle.mainBundle.privateFrameworksPath
            stringByAppendingPathComponent:@"PocketJJITCoordinator.framework/PocketJJITCoordinator"];
        void *handle = dlopen(framework.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        Class<PocketJJITCoordinatorAPI> coordinator =
            (Class<PocketJJITCoordinatorAPI>)NSClassFromString(@"PocketJJITCoordinator");
        if (handle && coordinator) {
            __block BOOL delivered = NO;
            __block dispatch_source_t stateTimer = dispatch_source_create(
                DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            void (^deliver)(BOOL, NSString *) = ^(BOOL success, NSString *message) {
                if (delivered) return;
                delivered = YES;
                if (stateTimer) {
                    dispatch_source_cancel(stateTimer);
                    stateTimer = nil;
                }
                [NSNotificationCenter.defaultCenter
                    postNotificationName:@"PocketJJITStateDidChangeNotification"
                                  object:nil
                                userInfo:@{@"enabled": @(success || isJITEnabled(YES))}];
                if (completion) completion(success, message ?: @"");
            };
            // StikJIT may continue post-enable housekeeping after the target is
            // already executable. Reflect the real process state immediately
            // instead of waiting for the entire helper request to return.
            dispatch_source_set_timer(stateTimer, DISPATCH_TIME_NOW,
                100 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
            dispatch_source_set_event_handler(stateTimer, ^{
                if (isJITEnabled(YES)) {
                    deliver(YES, localize(@"JIT 已启动", nil));
                }
            });
            dispatch_resume(stateTimer);
            [coordinator enableJITWithTargetPID:getpid() pairingData:pairingData
                completion:^(BOOL success, NSString *message) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        deliver(success, message ?: @"");
                    });
                }];
            return;
        }
        if (handle) dlclose(handle);
        if (completion) completion(NO, localize(@"内置 JIT Helper 未就绪。", nil));
        return;
    }
    if (completion) completion(NO, localize(@"当前系统需要使用外部 JIT 方式。", nil));
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"JIT";
    [ModernUITheme styleController:self]; [ModernUITheme styleTableView:self.tableView];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"帮助", nil)
        style:UIBarButtonItemStylePlain target:self action:@selector(showHelp)];
    self.tableView.estimatedRowHeight = 70;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pairingDidChange:)
        name:PocketJPairingHostDidChangeNotification object:nil];
}
- (void)dealloc { [self.statusTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [StikDebugEngine.sharedEngine synchronizePairingFileFromDocuments:nil];
    self.jitEnabled = isJITEnabled(YES);
    [self.tableView reloadData];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.visible = YES; [self startStatusPolling];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; self.visible = NO; [self stopStatusPolling];
}
- (void)applicationDidBecomeActive:(NSNotification *)note {
    [StikDebugEngine.sharedEngine synchronizePairingFileFromDocuments:nil];
    if (!self.visible) return;
    self.jitEnabled = isJITEnabled(YES);
    [self.tableView reloadData]; [self startStatusPolling];
}
- (void)applicationWillResignActive:(NSNotification *)note { [self stopStatusPolling]; }
- (void)pairingDidChange:(NSNotification *)note { if (self.visible) [self.tableView reloadData]; }
- (void)stopStatusPolling {
    [self.statusTimer invalidate]; self.statusTimer = nil;
    self.probeGeneration++; self.vpnChecking = NO;
}
- (void)startStatusPolling {
    [self stopStatusPolling];
    if (!self.visible || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    [self refreshLocalDevVPNStatus];
    __weak typeof(self) weakSelf = self;
    self.statusTimer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshLocalDevVPNStatus];
    }];
    self.statusTimer.tolerance = 0.1;
    [NSRunLoop.mainRunLoop addTimer:self.statusTimer forMode:NSRunLoopCommonModes];
}
- (void)refreshLocalDevVPNStatus {
    if (self.vpnChecking || !self.visible || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    self.vpnChecking = YES;
    NSUInteger generation = self.probeGeneration;
    __weak typeof(self) weakSelf = self;
    [StikDebugEngine.sharedEngine checkLocalDevVPNWithCompletion:^(BOOL connected) {
        typeof(self) self = weakSelf;
        if (!self || !self.visible || self.probeGeneration != generation) return;
        self.vpnChecking = NO;
        BOOL jit = isJITEnabled(YES);
        BOOL changed = !self.vpnHasResult || connected != self.vpnConnected || jit != self.jitEnabled;
        self.vpnHasResult = YES; self.vpnConnected = connected; self.jitEnabled = jit;
        if (jit) self.enabling = NO;
        if (changed) [self.tableView reloadData];
    }];
}
- (void)openLocalDevVPN {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"localdevvpn://"] options:@{} completionHandler:^(BOOL opened) {
        if (!opened) dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://apps.apple.com/us/app/localdevvpn/id6755608044"] options:@{} completionHandler:nil];
        });
    }];
}
- (void)showHelp {
    NSString *support = StikDebugViewController.setupState == PocketJJITSetupStateUnavailable
        ? localize(@"系统版本不支持", nil) : localize(@"系统支持 StikDebug", nil);
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@", support,
        localize(@"先准备配对文件，再连接 LocalDevVPN，最后开启 JIT。本机配对需 iOS 27 或更高版本；其他系统可从电脑获取文件后导入。", nil)];
    showDialog(localize(@"JIT 帮助", nil), message);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 1 ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? localize(@"连接准备", nil) : nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 2) return nil;
    return self.lastStatus.length ? self.lastStatus : localize(@"每次重新启动应用后，需要再次开启。", nil);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    [ModernUITheme styleCell:cell destructive:NO];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    if (path.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UILabel *title = [UILabel new];
        title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle2]
            scaledFontForFont:[UIFont systemFontOfSize:23 weight:UIFontWeightSemibold]];
        title.adjustsFontForContentSizeCategory = YES; title.numberOfLines = 0;
        title.text = self.jitEnabled ? localize(@"JIT 已开启", nil) : localize(@"JIT 未开启", nil);
        UILabel *detail = [UILabel new]; detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        detail.adjustsFontForContentSizeCategory = YES; detail.textColor = UIColor.secondaryLabelColor; detail.numberOfLines = 0;
        if (self.jitEnabled) detail.text = localize(@"可以返回启动游戏", nil);
        else if (StikDebugViewController.setupState == PocketJJITSetupStateUnavailable) detail.text = localize(@"系统版本不支持", nil);
        else if (!StikDebugEngine.sharedEngine.hasPairingFile) detail.text = localize(@"请先准备配对文件", nil);
        else if (!self.vpnHasResult) detail.text = localize(@"正在检测连接…", nil);
        else detail.text = localize(self.vpnConnected ? @"连接准备已完成" : @"等待 LocalDevVPN 连接", nil);
        UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail]];
        labels.axis = UILayoutConstraintAxisVertical; labels.spacing = 5;
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.jitEnabled ? @"checkmark.circle.fill" : @"bolt.fill"]];
        icon.tintColor = ModernUITheme.accentColor; icon.contentMode = UIViewContentModeScaleAspectFit;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, labels]];
        stack.alignment = UIStackViewAlignmentCenter; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [icon.widthAnchor constraintEqualToConstant:34], [icon.heightAnchor constraintEqualToConstant:38],
            [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
            [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:24],
            [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-24]]];
    } else if (path.section == 1) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (path.row == 0) {
            BOOL paired = StikDebugEngine.sharedEngine.hasPairingFile;
            cell.textLabel.text = localize(@"配对文件", nil);
            cell.detailTextLabel.text = localize(paired ? @"已就绪" : @"未配置", nil);
            cell.detailTextLabel.textColor = paired ? ModernUITheme.accentColor : UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"doc.badge.gearshape"];
        } else {
            cell.textLabel.text = @"LocalDevVPN";
            cell.detailTextLabel.text = !self.vpnHasResult ? localize(@"正在检测…", nil)
                : localize(self.vpnConnected ? @"已连接" : @"未连接", nil);
            cell.detailTextLabel.textColor = self.vpnHasResult && self.vpnConnected ? ModernUITheme.accentColor : UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"network.badge.shield.half.filled"];
        }
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = UIColor.clearColor;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        PocketJJITSetupState state = StikDebugViewController.setupState;
        NSString *title = self.enabling ? localize(@"正在开启 JIT…", nil)
            : localize(state == PocketJJITSetupStateEnabled ? @"JIT 已开启" : @"开启 JIT", nil);
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *config = [ModernUITheme primaryButtonConfigurationWithTitle:title image:nil];
            config.baseBackgroundColor = ModernUITheme.accentColor;
            config.showsActivityIndicator = self.enabling; button.configuration = config;
        } else {
            [button setTitle:title forState:UIControlStateNormal]; button.backgroundColor = ModernUITheme.accentColor;
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            [ModernUITheme styleContinuousButton:button cornerRadius:18];
        }
        button.enabled = !self.enabling && state == PocketJJITSetupStateReady;
        [button addTarget:self action:@selector(enableJIT) forControlEvents:UIControlEventTouchUpInside];
        button.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
            [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:56]]];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    if (path.row == 0) [self.navigationController pushViewController:[PocketJPairingFileViewController new] animated:YES];
    else [self openLocalDevVPN];
}
- (void)enableJIT {
    if (self.enabling || self.jitEnabled) return;
    self.enabling = YES;
    self.lastStatus = localize(@"正在打开独立 JIT 执行进程…", nil);
    [self.tableView reloadData];
    if (@available(iOS 26.0, *)) {
        __weak typeof(self) weakSelf = self;
        [StikDebugViewController enableEmbeddedJITWithCompletion:
            ^(BOOL success, NSString *message) {
                weakSelf.enabling = NO;
                weakSelf.jitEnabled = success || isJITEnabled(YES);
                weakSelf.lastStatus = success ? nil : [weakSelf userFacingErrorMessage:message];
                [weakSelf.tableView reloadData];
                if (!success) showDialog(localize(@"无法开启 JIT", nil), weakSelf.lastStatus);
            }];
        return;
    }

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"com.Erico.PocketJLauncher";
    NSString *escaped = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:
        NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *URL = [NSURL URLWithString:[NSString stringWithFormat:
        @"stikdebug://enable-jit?bundle-id=%@", escaped]];
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication openURL:URL options:@{} completionHandler:^(BOOL success) {
        weakSelf.enabling = NO;
        weakSelf.lastStatus = success
            ? localize(@"已交给 StikDebug。请在打开的界面确认开启 JIT，完成后返回 PocketJ Launcher。", nil)
            : localize(@"未找到可用的独立 StikDebug。同一 iOS 进程不能安全地附加自己，否则会永久卡死。", nil);
        [weakSelf.tableView reloadData];
        if (!success) showDialog(localize(@"无法开启 JIT", nil), weakSelf.lastStatus);
    }];
}

- (NSString *)userFacingErrorMessage:(NSString *)message {
    NSString *result = message.length ? message : localize(@"未知错误", nil);
    NSString *lowercase = result.lowercaseString;
    BOOL pairingError =
        [lowercase containsString:@"pairing file"] ||
        [lowercase containsString:@"pairingfile"] ||
        [lowercase containsString:@"public key"] ||
        [lowercase containsString:@"private key"] ||
        [lowercase containsString:@"invalid plist"] ||
        [lowercase containsString:@"failed to read pairing"];
    if (pairingError) {
        return [result stringByAppendingFormat:@"\n\n%@",
            localize(@"配对文件错误，请重新生成并导入本机配对文件。", nil)];
    }

    BOOL connectionError =
        [lowercase containsString:@"timed out connecting"] ||
        [lowercase containsString:@"connection refused"] ||
        [lowercase containsString:@"network is unreachable"] ||
        [lowercase containsString:@"no route to host"] ||
        [lowercase containsString:@"could not connect to 10.7.0.1"];
    if (connectionError) {
        return [result stringByAppendingFormat:@"\n\n%@",
            localize(@"请确保 LocalDevVPN 已开启后重试。", nil)];
    }
    return result;
}

@end
