#import "StikDebugViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <unistd.h>

#import "StikDebugEngine.h"
#import "../ModernUITheme.h"
#import "../UIKit+hook.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

@interface StikDebugViewController ()
@property(nonatomic) BOOL enabling;
@property(nonatomic) BOOL jitEnabled;
@property(nonatomic) BOOL pairingImportFailed;
@property(nonatomic) BOOL vpnChecking;
@property(nonatomic) BOOL vpnConnected;
@property(nonatomic, copy) NSString *lastStatus;
@property(nonatomic, strong) UIButton *enableButton;
- (NSString *)userFacingErrorMessage:(NSString *)message;
- (void)refreshLocalDevVPNStatus;
@end

@protocol PocketJJITCoordinatorAPI <NSObject>
+ (void)enableJITWithTargetPID:(int32_t)targetPID
                   pairingData:(NSData *)pairingData
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

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"JIT";
    self.jitEnabled = isJITEnabled(YES);
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68;
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refreshLocalDevVPNStatus];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [StikDebugEngine.sharedEngine synchronizePairingFileFromDocuments:nil];
    self.jitEnabled = isJITEnabled(YES);
    [self refreshLocalDevVPNStatus];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSError *syncError = nil;
    if (![StikDebugEngine.sharedEngine synchronizePairingFileFromDocuments:&syncError] && syncError) {
        self.pairingImportFailed = YES;
        self.lastStatus = syncError.localizedDescription;
    }
    self.jitEnabled = isJITEnabled(YES);
    if (self.jitEnabled) self.enabling = NO;
    [self refreshLocalDevVPNStatus];
    [self.tableView reloadData];
}

- (void)refreshLocalDevVPNStatus {
    if (self.vpnChecking) return;
    self.vpnChecking = YES;
    __weak typeof(self) weakSelf = self;
    [StikDebugEngine.sharedEngine checkLocalDevVPNWithCompletion:^(BOOL connected) {
        weakSelf.vpnChecking = NO;
        weakSelf.vpnConnected = connected;
        if (weakSelf.isViewLoaded) [weakSelf.tableView reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return 2;
    if (section == 2) return 2;
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return localize(@"JIT 状态", nil);
    if (section == 1) return localize(@"连接准备", nil);
    if (section == 2) return localize(@"配对文件管理", nil);
    return nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return localize(@"JIT 是否开启与系统是否支持分别检测，互不混淆。", nil);
    if (section == 1) return localize(@"完成配对文件和 LocalDevVPN 两项准备后即可开启 JIT。", nil);
    if (section == 2) return localize(@"支持 iLoader 写入 Documents/pairingFile.plist，也可导出供其他应用使用或从本机删除。", nil);
    if (section == 3) return localize(@"开启前请先导入本机配对文件，并确保 LocalDevVPN 已启动。", nil);
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL actionRow = indexPath.section == 3;
    NSString *identifier = actionRow ? @"JITActionCell" : @"StikCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    [ModernUITheme styleCell:cell destructive:NO];
    if (indexPath.section == 0) {
        PocketJJITSetupState state = StikDebugViewController.setupState;
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:
                self.jitEnabled ? @"bolt.circle.fill" : @"bolt.slash.circle"];
            cell.textLabel.text = localize(@"JIT 运行状态", nil);
            cell.detailTextLabel.text = self.jitEnabled
                ? localize(@"JIT 已开启", nil) : localize(@"JIT 未开启", nil);
            cell.detailTextLabel.textColor = self.jitEnabled
                ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
        } else {
            BOOL supported = state != PocketJJITSetupStateUnavailable;
            cell.imageView.image = [UIImage systemImageNamed:
                supported ? @"checkmark.shield.fill" : @"xmark.shield"];
            cell.textLabel.text = localize(@"系统支持状态", nil);
            cell.detailTextLabel.text = supported
                ? localize(@"系统支持 StikDebug", nil)
                : localize(@"系统版本不支持", nil);
            cell.detailTextLabel.textColor = supported
                ? UIColor.systemGreenColor : UIColor.systemRedColor;
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.badge.plus"];
        cell.textLabel.text = localize(@"① 导入配对文件", nil);
        BOOL imported = StikDebugEngine.sharedEngine.hasPairingFile;
        cell.detailTextLabel.text = imported
            ? localize(@"已导入", nil)
            : (self.pairingImportFailed
                ? (self.lastStatus.length ? self.lastStatus : localize(@"导入失败", nil))
                : localize(@"未导入", nil));
    } else if (indexPath.section == 1) {
        cell.imageView.image = [UIImage systemImageNamed:@"network.badge.shield.half.filled"];
        cell.textLabel.text = localize(@"② 打开 LocalDevVPN", nil);
        cell.detailTextLabel.text = self.vpnChecking
            ? localize(@"正在检测…", nil)
            : (self.vpnConnected ? localize(@"已连接", nil) : localize(@"未连接", nil));
        cell.detailTextLabel.textColor = self.vpnConnected
            ? UIColor.systemGreenColor : UIColor.systemRedColor;
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
        cell.textLabel.text = localize(@"导出配对文件", nil);
        cell.detailTextLabel.text = StikDebugEngine.sharedEngine.hasPairingFile
            ? localize(@"导出当前配对文件供其他应用使用", nil)
            : localize(@"请先导入配对文件", nil);
        cell.selectionStyle = StikDebugEngine.sharedEngine.hasPairingFile
            ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessoryType = StikDebugEngine.sharedEngine.hasPairingFile
            ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    } else if (indexPath.section == 2) {
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
        cell.textLabel.text = localize(@"删除配对文件", nil);
        cell.detailTextLabel.text = localize(@"从 PocketJ Launcher 中移除本机配对凭据", nil);
        cell.selectionStyle = StikDebugEngine.sharedEngine.hasPairingFile
            ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [[cell.contentView viewWithTag:8174] removeFromSuperview];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = 8174;
        PocketJJITSetupState state = StikDebugViewController.setupState;
        NSString *title = state == PocketJJITSetupStateEnabled
            ? localize(@"JIT 已启动", nil)
            : (state == PocketJJITSetupStateUnavailable
                ? localize(@"不可用", nil)
                : (state == PocketJJITSetupStateWaitingConfiguration
                    ? localize(@"等待配置", nil)
                    : (self.enabling ? localize(@"正在开启 JIT…", nil)
                                     : localize(@"开启 JIT", nil))));
        UIImage *image = [UIImage systemImageNamed:
            self.jitEnabled ? @"checkmark.circle.fill" : @"bolt.fill"];
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *configuration =
                [ModernUITheme primaryButtonConfigurationWithTitle:title image:image];
            configuration.baseBackgroundColor = UIColor.systemGreenColor;
            configuration.showsActivityIndicator = self.enabling;
            if (state == PocketJJITSetupStateReady && !self.enabling) {
                configuration.subtitle = localize(@"就绪", nil);
            }
            if (self.enabling) configuration.image = nil;
            button.configuration = configuration;
        } else {
            [button setTitle:title forState:UIControlStateNormal];
            [button setImage:image forState:UIControlStateNormal];
            button.tintColor = UIColor.whiteColor;
            button.backgroundColor = UIColor.systemGreenColor;
            [ModernUITheme styleContinuousButton:button cornerRadius:18.0];
        }
        button.enabled = !self.enabling && state == PocketJJITSetupStateReady;
        [button addTarget:self action:@selector(enableJIT)
          forControlEvents:UIControlEventTouchUpInside];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [button.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8.0],
            [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8.0],
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:54.0],
        ]];
        self.enableButton = button;
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        BOOL imported = StikDebugEngine.sharedEngine.hasPairingFile;
        cell.detailTextLabel.textColor = imported
            ? UIColor.systemGreenColor : UIColor.systemRedColor;
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        [ModernUITheme styleCell:cell destructive:YES];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) {
        NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObject:UTTypePropertyList];
        UTType *pairing = [UTType typeWithFilenameExtension:@"mobiledevicepairing" conformingToType:UTTypeData];
        if (pairing) [types addObject:pairing];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (indexPath.section == 1) {
        NSURL *URL = [NSURL URLWithString:@"https://apps.apple.com/us/app/localdevvpn/id6755608044"];
        [UIApplication.sharedApplication openURL:URL options:@{} completionHandler:nil];
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        if (!StikDebugEngine.sharedEngine.hasPairingFile) return;
        NSError *error = nil;
        NSURL *URL = [StikDebugEngine.sharedEngine exportablePairingFileURL:&error];
        if (!URL) {
            showDialog(localize(@"导出失败", nil), error.localizedDescription ?: localize(@"未知错误", nil));
            return;
        }
        UIActivityViewController *share = [[UIActivityViewController alloc]
            initWithActivityItems:@[URL] applicationActivities:nil];
        share.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
        [self presentViewController:share animated:YES completion:nil];
    } else if (indexPath.section == 2) {
        if (!StikDebugEngine.sharedEngine.hasPairingFile) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:
            localize(@"删除配对文件？", nil)
            message:localize(@"删除后需要重新通过 iLoader 或文件选择器导入。", nil)
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
            style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"删除", nil)
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                NSError *error = nil;
                if (![StikDebugEngine.sharedEngine deletePairingFile:&error]) {
                    showDialog(localize(@"删除失败", nil), error.localizedDescription ?: localize(@"未知错误", nil));
                    return;
                }
                weakSelf.pairingImportFailed = NO;
                weakSelf.lastStatus = nil;
                [weakSelf.tableView reloadData];
            }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)URLs {
    NSError *error = nil;
    if ([StikDebugEngine.sharedEngine importPairingFileAtURL:URLs.firstObject error:&error]) {
        self.pairingImportFailed = NO;
        self.lastStatus = localize(@"配对文件导入成功。需要时请手动点击“立即开启 JIT”。", nil);
        [self.tableView reloadData];
    } else {
        self.pairingImportFailed = YES;
        self.lastStatus = error.localizedDescription ?: localize(@"配对文件导入失败。", nil);
        [self.tableView reloadData];
    }
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
                weakSelf.lastStatus = success ? message : [weakSelf userFacingErrorMessage:message];
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
