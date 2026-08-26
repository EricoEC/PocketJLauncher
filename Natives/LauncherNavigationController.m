#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "authenticator/BaseAuthenticator.h"
#import "AFNetworking.h"
#import "ALTServerConnection.h"
#import "CustomControlsViewController.h"
#import "DownloadProgressViewController.h"
#import "JavaGUIViewController.h"
#import "JavaLauncher.h"
#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "installer/FabricUtils.h"
#import "installer/modpack/ModpackAPI.h"
#import "installer/modpack/ModrinthAPI.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLPickerView.h"
#import "PLProfiles.h"
#import "stikdebug/StikDebugEngine.h"
#import "stikdebug/StikDebugViewController.h"
#import "ModernRootTabBarController.h"
#import "UIKit+AFNetworking.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#import <objc/runtime.h>
#include <sys/time.h>

#define AUTORESIZE_MASKS UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin

static void *ProgressObserverContext = &ProgressObserverContext;

NSNotificationName const LauncherTaskStateDidChangeNotification =
    @"LauncherTaskStateDidChangeNotification";
static NSString *const LauncherInterruptedDownloadKey =
    @"LauncherInterruptedDownloadIdentifier";
static NSString *const LauncherVerifiedCompleteKey =
    @"LauncherVerifiedCompleteIdentifier";
static NSString *const LauncherDownloadStateMigrationKey =
    @"LauncherDownloadStateMigrationV3";
static NSString *const LauncherInterruptedDownloadsKey =
    @"LauncherInterruptedDownloadIdentifiers";
static NSString *const LauncherVerifiedCompletesKey =
    @"LauncherVerifiedCompleteIdentifiers";

@interface LauncherNavigationController () <UIDocumentPickerDelegate, UIPickerViewDataSource, PLPickerViewDelegate, UIPopoverPresentationControllerDelegate> {
}

@property(nonatomic) MinecraftResourceDownloadTask* task;
@property(nonatomic) UINavigationController* progressVC;
@property(nonatomic) NSArray* globalToolbarItems;
@property(nonatomic) PLPickerView* versionPickerView;
@property(nonatomic) PickTextField* versionTextField;
@property(nonatomic) UIButton* buttonInstall;
@property(nonatomic) UIBarButtonItem* buttonInstallItem;
@property(nonatomic) int profileSelectedAt;
@property(nonatomic) BOOL currentTaskPaused;
@property(nonatomic) BOOL activeTaskRequiresDownload;
@property(nonatomic, copy) NSString *activeDownloadIdentifier;
@property(nonatomic, strong) NSURLSessionTask *loaderInstallTask;
@property(nonatomic) BOOL jitEnabling;
@property(nonatomic) BOOL jitReadyFeedback;
@property(nonatomic) BOOL deferGameLaunchAfterJITEnable;
@property(nonatomic, copy) NSString *launchTaskPhase;
@property(nonatomic) BOOL downloadPlanResolved;

@end

@implementation LauncherNavigationController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIInterfaceOrientationMask childMask =
        self.topViewController.supportedInterfaceOrientations;
    return childMask ?: (UIInterfaceOrientationMaskPortrait |
        UIInterfaceOrientationMaskLandscapeLeft |
        UIInterfaceOrientationMaskLandscapeRight);
}

- (void)postTaskActive:(BOOL)active {
    double fraction = self.task ? self.task.progress.fractionCompleted : 0.0;
    if (self.jitReadyFeedback) fraction = 1.0;
    [NSNotificationCenter.defaultCenter
        postNotificationName:LauncherTaskStateDidChangeNotification
                      object:self
                    userInfo:@{
                        @"active": @(active),
                        @"paused": @(self.currentTaskPaused),
                        @"downloading": @(self.activeTaskRequiresDownload),
                        @"loaderInstalling": @(self.loaderInstallTask != nil),
                        @"jitEnabling": @(self.jitEnabling),
                        @"jitReady": @(self.jitReadyFeedback),
                        @"fraction": @(MAX(0.0, MIN(fraction, 1.0))),
                        @"phase": self.launchTaskPhase ?: @""
                    }];
}

- (NSString *)phaseForDownloadTask:(MinecraftResourceDownloadTask *)task percent:(NSInteger)percent {
    NSArray *files = nil, *progresses = nil;
    [task snapshotFileList:&files progressList:&progresses];
    NSString *activeFile = nil;
    for (NSUInteger index = 0; index < MIN(files.count, progresses.count); index++) {
        NSProgress *fileProgress = progresses[index];
        if (!fileProgress.finished) { activeFile = files[index]; break; }
    }
    NSString *phase = localize(@"正在下载 Minecraft", nil);
    NSString *lower = activeFile.lowercaseString ?: @"";
    if ([lower containsString:@"/assets/"] || [lower containsString:@"\\assets\\"]) {
        phase = localize(@"正在下载资源文件", nil);
    } else if ([lower containsString:@"/libraries/"] || [lower containsString:@"\\libraries\\"]) {
        phase = localize(@"正在下载依赖库", nil);
    } else if ([lower hasSuffix:@".json"]) {
        phase = localize(@"正在下载版本信息", nil);
    } else if ([lower hasSuffix:@".jar"]) {
        phase = localize(@"正在下载游戏客户端", nil);
    }
    return [NSString stringWithFormat:localize(@"%@ · %ld%%", nil), phase, (long)percent];
}

- (void)showJITReadyFeedbackThen:(dispatch_block_t)completion {
    self.deferGameLaunchAfterJITEnable = NO;
    self.jitReadyFeedback = YES;
    self.jitEnabling = YES;
    self.launchTaskPhase = localize(@"JIT 已开启，可继续游戏", nil);
    [self postTaskActive:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.jitReadyFeedback = NO;
        self.jitEnabling = NO;
        self.launchTaskPhase = nil;
        self.activeDownloadIdentifier = nil;
        [self postTaskActive:NO];
        if (completion) completion();
    });
}

- (BOOL)hasActiveLaunchTask {
    BOOL hasTask = self.task != nil || self.loaderInstallTask != nil || self.jitEnabling;
    return hasTask &&
        [self.activeDownloadIdentifier
            isEqualToString:self.selectedDownloadIdentifier];
}

- (NSString *)selectedDownloadIdentifier {
    NSString *gameDirectory =
        getPrefObject(@"general.game_directory") ?: @"";
    NSString *instancePath = @(getenv("POJAV_GAME_DIR")) ?: @"";
    NSString *identityPath =
        [instancePath stringByAppendingPathComponent:@".pocketj-instance-id"];
    NSString *instanceIdentity = [NSString
        stringWithContentsOfFile:identityPath
                       encoding:NSUTF8StringEncoding
                          error:nil];
    instanceIdentity = [instanceIdentity
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (instanceIdentity.length == 0 && instancePath.length > 0) {
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:instancePath
                                               isDirectory:&isDirectory] &&
            isDirectory) {
            instanceIdentity = NSUUID.UUID.UUIDString;
            [instanceIdentity writeToFile:identityPath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:nil];
        }
    }
    NSString *profileName = PLProfiles.current.selectedProfileName ?: @"";
    NSString *versionId =
        PLProfiles.current.selectedProfile[@"lastVersionId"] ?: @"";
    // The UUID survives renames but disappears with the instance directory.
    // Recreating a directory with the same visible name therefore starts with
    // a clean UI state instead of inheriting "Resume download" from its namesake.
    return [NSString stringWithFormat:@"%@|%@|%@",
        instanceIdentity.length ? instanceIdentity : gameDirectory,
        profileName, versionId];
}

- (NSMutableDictionary *)downloadStatesForKey:(NSString *)key {
    NSDictionary *stored =
        [NSUserDefaults.standardUserDefaults dictionaryForKey:key];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)setDownloadState:(BOOL)enabled
              identifier:(NSString *)identifier
                     key:(NSString *)key {
    if (identifier.length == 0) return;
    NSMutableDictionary *states = [self downloadStatesForKey:key];
    if (enabled) {
        states[identifier] = @YES;
    } else {
        [states removeObjectForKey:identifier];
    }
    [NSUserDefaults.standardUserDefaults setObject:states forKey:key];
}

- (void)migrateLegacyDownloadStatesIfNeeded {
    if ([NSUserDefaults.standardUserDefaults
            boolForKey:LauncherDownloadStateMigrationKey]) {
        return;
    }
    // V2 used one global string and could not distinguish instances whose
    // selected profile shared the name "default". Drop only that ambiguous
    // state; the kernel will verify the selected instance on the next launch.
    [NSUserDefaults.standardUserDefaults
        removeObjectForKey:LauncherInterruptedDownloadKey];
    [NSUserDefaults.standardUserDefaults
        removeObjectForKey:LauncherVerifiedCompleteKey];
    [NSUserDefaults.standardUserDefaults
        setBool:YES forKey:LauncherDownloadStateMigrationKey];
}

- (void)markSelectedDownloadInterrupted {
    NSString *identifier =
        self.activeDownloadIdentifier ?: self.selectedDownloadIdentifier;
    [self setDownloadState:YES
               identifier:identifier
                      key:LauncherInterruptedDownloadsKey];
    [self setDownloadState:NO
               identifier:identifier
                      key:LauncherVerifiedCompletesKey];
}

- (void)clearSelectedDownloadInterrupted {
    NSString *completedIdentifier =
        self.activeDownloadIdentifier ?: self.selectedDownloadIdentifier;
    [self setDownloadState:NO
               identifier:completedIdentifier
                      key:LauncherInterruptedDownloadsKey];
}

- (BOOL)selectedProfileHasInterruptedDownload {
    [self migrateLegacyDownloadStatesIfNeeded];
    return [[self downloadStatesForKey:LauncherInterruptedDownloadsKey]
        [self.selectedDownloadIdentifier] boolValue];
}

- (BOOL)selectedProfileNeedsDownload {
    [self migrateLegacyDownloadStatesIfNeeded];
    if ([PLProfiles.current.selectedProfile[@"pocketjPendingModpack"]
            isKindOfClass:NSDictionary.class]) {
        return YES;
    }
    if ([PLProfiles.current.selectedProfile[@"pocketjResourcesVerified"]
            isEqual:@NO]) {
        return YES;
    }
    if ([[self downloadStatesForKey:LauncherVerifiedCompletesKey]
            [self.selectedDownloadIdentifier] boolValue]) {
        return NO;
    }
    NSString *versionId =
        PLProfiles.current.selectedProfile[@"lastVersionId"];
    if ([versionId isEqualToString:@"latest-release"]) {
        versionId = getPrefObject(@"internal.latest_version.release");
    } else if ([versionId isEqualToString:@"latest-snapshot"]) {
        versionId = getPrefObject(@"internal.latest_version.snapshot");
    }
    return versionId.length == 0 || ![self isVersionInstalled:versionId];
}

- (BOOL)isCurrentLaunchTaskPaused {
    return self.hasActiveLaunchTask && self.currentTaskPaused;
}

- (void)pauseCurrentLaunchTask {
    if (!self.task || self.currentTaskPaused) {
        return;
    }
    self.currentTaskPaused = YES;
    self.launchTaskPhase = localize(@"下载已暂停", nil);
    [self.task pause];
    [self postTaskActive:YES];
}

- (void)resumeCurrentLaunchTask {
    if (!self.task || !self.currentTaskPaused) {
        return;
    }
    self.currentTaskPaused = NO;
    self.launchTaskPhase = localize(@"正在继续下载…", nil);
    [self.task resume];
    [self postTaskActive:YES];
}

- (void)cancelCurrentLaunchTask {
    MinecraftResourceDownloadTask *task = self.task;
    NSURLSessionTask *loaderTask = self.loaderInstallTask;
    if (!task && !loaderTask && !self.jitEnabling) {
        return;
    }

    if (self.jitEnabling) return;

    if (loaderTask) {
        [loaderTask cancel];
        self.loaderInstallTask = nil;
        self.currentTaskPaused = NO;
        self.activeTaskRequiresDownload = NO;
        self.activeDownloadIdentifier = nil;
        [self setInteractionEnabled:YES forDownloading:YES];
        [self postTaskActive:NO];
        return;
    }

    @try {
        [task.progress removeObserver:self
                           forKeyPath:@"fractionCompleted"
                              context:ProgressObserverContext];
    } @catch (__unused NSException *exception) {
    }
    self.progressViewMain.observedProgress = nil;
    [task cancel];
    if (self.activeTaskRequiresDownload) {
        [self markSelectedDownloadInterrupted];
    } else {
        [self clearSelectedDownloadInterrupted];
    }
    self.task = nil;
    self.currentTaskPaused = NO;
    self.activeTaskRequiresDownload = NO;
    self.activeDownloadIdentifier = nil;
    [self.progressVC dismissViewControllerAnimated:YES completion:nil];
    self.progressVC = nil;
    [self setInteractionEnabled:YES forDownloading:YES];
    [self postTaskActive:NO];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if ([self respondsToSelector:@selector(setNeedsUpdateOfScreenEdgesDeferringSystemGestures)]) {
        [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
    }
    UIToolbar *targetToolbar = self.toolbar;
    BOOL hasLiquidGlass = _UISolariumEnabled && _UISolariumEnabled();
    
    if(hasLiquidGlass) {
        self.versionTextField = [[PickTextField alloc] initWithFrame:CGRectMake(0, 0, MIN(self.view.frame.size.width,self.view.frame.size.height)*0.8 - 40, 36)];
        self.progressViewMain = [[UIProgressView alloc] initWithFrame:CGRectMake(20, -5, self.versionTextField.frame.size.width-40, 0)];
    } else {
        self.versionTextField = [[PickTextField alloc] initWithFrame:CGRectMake(4, 4, self.toolbar.frame.size.width * 0.8 - 8, self.toolbar.frame.size.height - 8)];
        self.progressViewMain = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, targetToolbar.frame.size.width, 0)];
    }
    [self.versionTextField addTarget:self.versionTextField action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
    self.versionTextField.autoresizingMask = AUTORESIZE_MASKS;
    self.versionTextField.placeholder = localize(@"localization.field.specify_version", nil);
    self.versionTextField.leftView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    self.versionTextField.rightView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"SpinnerArrow"] _imageWithSize:CGSizeMake(30, 30)]];
    self.versionTextField.rightView.frame = CGRectMake(0, 0, self.versionTextField.frame.size.height * 0.9, self.versionTextField.frame.size.height * 0.9);
    self.versionTextField.leftViewMode = UITextFieldViewModeAlways;
    self.versionTextField.rightViewMode = UITextFieldViewModeAlways;
    self.versionTextField.textAlignment = NSTextAlignmentCenter;

    self.versionPickerView = [[PLPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;

    [self reloadProfileList];

    self.versionTextField.inputView = self.versionPickerView;
    [self.versionTextField setupDoneButtonWithTarget:self action:@selector(versionClosePicker)];

    UIView *textFieldContainer = nil;
    if(hasLiquidGlass) {
        textFieldContainer = [[UIView alloc] initWithFrame:self.versionTextField.frame];
        [textFieldContainer addSubview:self.progressViewMain];
        self.buttonInstallItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"Play", nil)
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(performInstallOrShowDetails:)];
        self.buttonInstallItem.enabled = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.buttonInstallItem.buttonGlassView.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:0.5];
        });
        [textFieldContainer addSubview:self.versionTextField];
        UIBarButtonItem *textFieldItem = [[UIBarButtonItem alloc] initWithCustomView:textFieldContainer];
        self.globalToolbarItems = @[
            textFieldItem,
            self.buttonInstallItem,
        ];
    } else {
        self.buttonInstall = [UIButton buttonWithType:UIButtonTypeSystem];
        setButtonPointerInteraction(self.buttonInstall);
        [self.buttonInstall setTitle:localize(@"Play", nil) forState:UIControlStateNormal];
        self.buttonInstall.autoresizingMask = AUTORESIZE_MASKS;
        self.buttonInstall.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1.0];
        self.buttonInstall.layer.cornerRadius = 5;
        self.buttonInstall.frame = CGRectMake(self.toolbar.frame.size.width * 0.8, 4, self.toolbar.frame.size.width * 0.2, self.toolbar.frame.size.height - 8);
        self.buttonInstall.tintColor = UIColor.whiteColor;
        self.buttonInstall.enabled = NO;
        [self.buttonInstall addTarget:self action:@selector(performInstallOrShowDetails:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [targetToolbar addSubview:self.progressViewMain];
        [targetToolbar addSubview:self.versionTextField];
        [targetToolbar addSubview:self.buttonInstall];
    }
    
    self.progressViewMain.autoresizingMask = AUTORESIZE_MASKS;
    self.progressViewMain.hidden = YES;
    self.progressText = [[UILabel alloc] initWithFrame:self.versionTextField.frame];
    self.progressText.adjustsFontSizeToFitWidth = YES;
    self.progressText.autoresizingMask = AUTORESIZE_MASKS;
    self.progressText.font = [self.progressText.font fontWithSize:16];
    self.progressText.textAlignment = NSTextAlignmentCenter;
    self.progressText.userInteractionEnabled = NO;
    
    if(hasLiquidGlass) {
        [textFieldContainer addSubview:self.progressText];
    } else {
        [targetToolbar addSubview:self.progressText];
    }

    [self fetchRemoteVersionList];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(receiveNotification:) 
        name:@"InstallModpack"
        object:nil];

    if ([BaseAuthenticator.current isKindOfClass:MicrosoftAuthenticator.class]) {
        // Perform token refreshment on startup
        [self setInteractionEnabled:NO forDownloading:NO];
        id callback = ^(id status, BOOL success) {
            status = [status description];
            self.progressText.text = status;
            if (status == nil) {
                [self setInteractionEnabled:YES forDownloading:NO];
            } else if (!success) {
                showDialog(localize(@"Error", nil), status);
            }
        };
        [BaseAuthenticator.current refreshTokenWithCallback:callback];
    }
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    [super setViewControllers:viewControllers animated:animated];
    if (![self.splitViewController isKindOfClass:NSClassFromString(@"ModernLauncherViewController")] &&
        !viewControllers.firstObject.toolbarItems && self.globalToolbarItems) {
        viewControllers.firstObject.toolbarItems = self.globalToolbarItems;
    }
}

- (BOOL)isVersionInstalled:(NSString *)versionId {
    NSString *localPath = [NSString stringWithFormat:@"%s/versions/%@", getenv("POJAV_GAME_DIR"), versionId];
    BOOL isDirectory;
    [NSFileManager.defaultManager fileExistsAtPath:localPath isDirectory:&isDirectory];
    return isDirectory;
}

- (void)fetchLocalVersionList {
    if (!localVersionList) {
        localVersionList = [NSMutableArray new];
    }
    [localVersionList removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *versionPath = [NSString stringWithFormat:@"%s/versions/", getenv("POJAV_GAME_DIR")];
    NSArray *list = [fileManager contentsOfDirectoryAtPath:versionPath error:Nil];
    for (NSString *versionId in list) {
        if (![self isVersionInstalled:versionId]) continue;
        [localVersionList addObject:@{
            @"id": versionId,
            @"type": @"custom"
        }];
    }
}

- (void)fetchRemoteVersionList {
    [(id)(self.buttonInstall ?: self.buttonInstallItem) setEnabled:NO];
    remoteVersionList = @[
        @{@"id": @"latest-release", @"type": @"release"},
        @{@"id": @"latest-snapshot", @"type": @"snapshot"}
    ].mutableCopy;

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager GET:@"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" parameters:nil headers:nil progress:^(NSProgress * _Nonnull progress) {
        self.progressViewMain.progress = progress.fractionCompleted;
    } success:^(NSURLSessionTask *task, NSDictionary *responseObject) {
        [remoteVersionList addObjectsFromArray:responseObject[@"versions"]];
        NSDebugLog(@"[VersionList] Got %d versions", remoteVersionList.count);
        setPrefObject(@"internal.latest_version", responseObject[@"latest"]);
        [(id)(self.buttonInstall ?: self.buttonInstallItem) setEnabled:YES];
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        NSDebugLog(@"[VersionList] Warning: Unable to fetch version list: %@", error.localizedDescription);
        [(id)(self.buttonInstall ?: self.buttonInstallItem) setEnabled:YES];
    }];
}

// Invoked by: startup, instance change event
- (void)reloadProfileList {
    // Reload local version list
    [self fetchLocalVersionList];
    // Reload launcher_profiles.json
    [PLProfiles updateCurrent];
    [self.versionPickerView reloadAllComponents];
    // Reload selected profile info
    NSArray *profileNames = PLProfiles.current.profiles.allKeys;
    NSString *selectedName = PLProfiles.current.selectedProfileName;
    if (selectedName.length == 0 || profileNames.count == 0) {
        self.profileSelectedAt = -1;
        return;
    }
    NSUInteger selectedIndex = [profileNames indexOfObject:selectedName];
    if (selectedIndex == NSNotFound) {
        self.profileSelectedAt = -1;
        // This instance has no profiles?
        return;
    }
    self.profileSelectedAt = (int)selectedIndex;
    [self.versionPickerView selectRow:self.profileSelectedAt inComponent:0 animated:NO];
    [self pickerView:self.versionPickerView didSelectRow:self.profileSelectedAt inComponent:0];
}

#pragma mark - Options
- (void)enterCustomControls {
    CustomControlsViewController *vc = [[CustomControlsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.setDefaultCtrl = ^(NSString *name){
        setPrefObject(@"control.default_ctrl", name);
    };
    vc.getDefaultCtrl = ^{
        return getPrefObject(@"control.default_ctrl");
    };
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)enterModInstaller {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/java-archive"]]
        asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter {
    [self enterModInstallerWithPath:path hitEnterAfterWindowShown:hitEnter requiredJavaVersion:0];
}

- (void)enterModInstallerWithPath:(NSString *)path
        hitEnterAfterWindowShown:(BOOL)hitEnter
        requiredJavaVersion:(int)requiredJavaVersion {
    JavaGUIViewController *vc = [[JavaGUIViewController alloc] init];
    vc.filepath = path;
    vc.hitEnterAfterWindowShown = hitEnter;
    vc.requiredJavaVersionOverride = requiredJavaVersion;
    if (!vc.requiredJavaVersion) {
        return;
    }
    [self invokeAfterJITEnabled:^{
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        NSLog(@"[ModInstaller] launching %@", vc.filepath);
        [self presentViewController:vc animated:YES completion:nil];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self enterModInstallerWithPath:url.path hitEnterAfterWindowShown:NO];
}

- (void)setInteractionEnabled:(BOOL)enabled forDownloading:(BOOL)downloading {
    self.versionTextField.alpha = enabled ? 1 : 0.2;
    self.versionTextField.enabled = enabled;
    self.progressViewMain.hidden = enabled;
    self.progressText.text = nil;
    if (downloading) {
        if(self.buttonInstall) {
            [self.buttonInstall setTitle:localize(enabled ? @"Play" : @"Details", nil) forState:UIControlStateNormal];
            self.buttonInstall.enabled = YES;
        } else {
            self.buttonInstallItem.title = localize(enabled ? @"Play" : @"Details", nil);
            self.buttonInstallItem.enabled = YES;
        }
    } else {
        self.buttonInstall.enabled = enabled;
        self.buttonInstallItem.enabled = enabled;
    }
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
}

- (void)presentPendingLoaderInstallerAtPath:(NSString *)path
                                     loader:(NSString *)loader
                           minecraftVersion:(NSString *)minecraftVersion
                              loaderVersion:(NSString *)loaderVersion {
    NSMutableDictionary *profile = PLProfiles.current.selectedProfile;
    profile[@"pocketjResourcesVerified"] = @NO;
    [PLProfiles.current save];
    NSArray *before = [NSFileManager.defaultManager contentsOfDirectoryAtPath:
        [NSString stringWithFormat:@"%s/versions", getenv("POJAV_GAME_DIR")] error:nil] ?: @[];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:getPrefObject(@"general.game_directory") ?: @"" forKey:@"PocketJPendingLoaderInstance"];
    [defaults setObject:PLProfiles.current.selectedProfileName ?: @"" forKey:@"PocketJPendingLoaderProfile"];
    [defaults setObject:loader forKey:@"PocketJPendingLoaderKind"];
    [defaults setObject:minecraftVersion forKey:@"PocketJPendingLoaderMinecraftVersion"];
    [defaults setObject:loaderVersion forKey:@"PocketJPendingLoaderVersion"];
    [defaults setObject:before forKey:@"PocketJPendingLoaderBeforeVersions"];
    [self setInteractionEnabled:YES forDownloading:YES];
    [self postTaskActive:NO];
    int requiredJava = PocketJRequiredJavaVersionForMinecraft(minecraftVersion);
    NSLog(@"[Loader Installer] %@ %@ for Minecraft %@ will use Java %d",
        loader, loaderVersion, minecraftVersion, requiredJava);
    [self enterModInstallerWithPath:path
            hitEnterAfterWindowShown:YES
            requiredJavaVersion:requiredJava];
}

- (void)installPendingLoaderForProfile:(NSMutableDictionary *)profile sender:(UIButton *)sender {
    if (self.loaderInstallTask || self.task) return;
    NSString *loader = profile[@"pocketjLoader"] ?: @"vanilla";
    NSString *minecraftVersion = profile[@"pocketjMinecraftVersion"] ?: profile[@"lastVersionId"];
    if ([minecraftVersion isEqualToString:@"latest-release"]) {
        minecraftVersion = getPrefObject(@"internal.latest_version.release") ?: minecraftVersion;
    } else if ([minecraftVersion isEqualToString:@"latest-snapshot"]) {
        minecraftVersion = getPrefObject(@"internal.latest_version.snapshot") ?: minecraftVersion;
    }
    NSString *loaderVersion = profile[@"pocketjLoaderVersion"] ?: @"";
    if (!minecraftVersion.length || !loaderVersion.length) {
        showDialog(localize(@"加载器配置不完整", nil),
            localize(@"请在编辑实例中选择 Minecraft 版本和加载器版本。", nil));
        return;
    }
    // Migrated instances may already contain the requested loader while the
    // old profile still points at Vanilla. Reuse that installation first.
    NSString *versionsRoot = [NSString stringWithFormat:@"%s/versions", getenv("POJAV_GAME_DIR")];
    for (NSString *candidate in [NSFileManager.defaultManager contentsOfDirectoryAtPath:versionsRoot error:nil] ?: @[]) {
        NSString *lower = candidate.lowercaseString;
        if (![lower containsString:loader.lowercaseString] ||
            ![lower containsString:loaderVersion.lowercaseString]) continue;
        if ([loader isEqualToString:@"forge"] && [lower containsString:@"neoforge"]) continue;
        NSString *jsonPath = [[versionsRoot stringByAppendingPathComponent:candidate]
            stringByAppendingPathComponent:[candidate stringByAppendingPathExtension:@"json"]];
        NSDictionary *metadata = parseJSONFromFile(jsonPath);
        NSString *base = metadata[@"inheritsFrom"];
        if (base.length && ![base isEqualToString:minecraftVersion]) continue;
        profile[@"lastVersionId"] = candidate;
        profile[@"pocketjLoaderInstallPending"] = @NO;
        [PLProfiles.current save];
        [NSNotificationCenter.defaultCenter postNotificationName:@"LauncherProfilesDidChangeNotification" object:nil];
        [self launchMinecraft:sender];
        return;
    }
    [self setInteractionEnabled:NO forDownloading:YES];
    self.activeDownloadIdentifier = self.selectedDownloadIdentifier;
    self.activeTaskRequiresDownload = YES;
    self.progressText.text = [NSString stringWithFormat:localize(@"正在安装 %@…", nil), loader.capitalizedString];
    __weak typeof(self) weakSelf = self;
    if ([loader isEqualToString:@"fabric"] || [loader isEqualToString:@"quilt"]) {
        NSString *vendor = [loader isEqualToString:@"quilt"] ? @"Quilt" : @"Fabric";
        NSString *format = [FabricUtils endpoints][vendor][@"json"];
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:format, minecraftVersion, loaderVersion]];
        __block NSURLSessionDataTask *task = nil;
        task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse *)response : nil;
            BOOL validResponse = !http || http.statusCode == 200;
            NSDictionary *metadata = data.length && validResponse
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *versionID = [metadata isKindOfClass:NSDictionary.class] ? metadata[@"id"] : nil;
            NSError *saveError = nil;
            if (versionID.length) {
                NSString *path = [NSString stringWithFormat:@"%s/versions/%@/%@.json", getenv("POJAV_GAME_DIR"), versionID, versionID];
                [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&saveError];
                if (!saveError) saveError = saveJSONToFile(metadata, path);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.loaderInstallTask != task) return;
                weakSelf.loaderInstallTask = nil;
                weakSelf.activeDownloadIdentifier = nil;
                weakSelf.activeTaskRequiresDownload = NO;
                if (error || saveError || !versionID.length) {
                    [weakSelf setInteractionEnabled:YES forDownloading:YES];
                    [weakSelf postTaskActive:NO];
                    NSString *detail = error.localizedDescription ?: saveError.localizedDescription;
                    if (!detail.length && http.statusCode != 200) {
                        detail = [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode];
                    }
                    showDialog(localize(@"加载器安装失败", nil),
                        detail ?: localize(@"服务器返回了无效的加载器信息。", nil));
                    return;
                }
                profile[@"lastVersionId"] = versionID;
                profile[@"pocketjLoaderInstallPending"] = @NO;
                profile[@"pocketjResourcesVerified"] = @NO;
                [PLProfiles.current save];
                [NSNotificationCenter.defaultCenter postNotificationName:@"LauncherProfilesDidChangeNotification" object:nil];
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                [weakSelf postTaskActive:NO];
                [weakSelf launchMinecraft:sender];
            });
        }];
        self.loaderInstallTask = task;
        self.launchTaskPhase = localize(@"正在下载模组加载器…", nil);
        [self postTaskActive:YES];
        [task resume];
        return;
    }

    NSString *forgePrefix = [minecraftVersion stringByAppendingString:@"-"];
    NSString *artifactVersion = [loader isEqualToString:@"forge"]
        ? ([loaderVersion hasPrefix:forgePrefix]
            ? loaderVersion
            : [NSString stringWithFormat:@"%@-%@", minecraftVersion, loaderVersion])
        : loaderVersion;
    NSString *urlString = [loader isEqualToString:@"forge"]
        ? [NSString stringWithFormat:@"https://maven.minecraftforge.net/net/minecraftforge/forge/%1$@/forge-%1$@-installer.jar", artifactVersion]
        : [NSString stringWithFormat:@"https://maven.neoforged.net/releases/net/neoforged/neoforge/%1$@/neoforge-%1$@-installer.jar", artifactVersion];
    NSString *cacheRoot = [@(getenv("POJAV_GAME_DIR"))
        stringByAppendingPathComponent:@".pocketj-cache/loaders"];
    [NSFileManager.defaultManager createDirectoryAtPath:cacheRoot
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *target = [cacheRoot stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@-%@-installer.jar", loader, artifactVersion]];
    unsigned long long cachedSize = [[NSFileManager.defaultManager
        attributesOfItemAtPath:target error:nil][NSFileSize] unsignedLongLongValue];
    if (cachedSize > 65536) {
        NSLog(@"[Loader Installer] Reusing cached installer %@", target.lastPathComponent);
        self.activeDownloadIdentifier = nil;
        self.activeTaskRequiresDownload = NO;
        [self presentPendingLoaderInstallerAtPath:target loader:loader
            minecraftVersion:minecraftVersion loaderVersion:loaderVersion];
        return;
    }
    __block NSURLSessionDownloadTask *task = nil;
    task = [[NSURLSession sharedSession] downloadTaskWithURL:[NSURL URLWithString:urlString]
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class]
            ? (NSHTTPURLResponse *)response : nil;
        if (!error && http && http.statusCode != 200) {
            error = [NSError errorWithDomain:@"PocketJLoaderDownload"
                code:http.statusCode userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:localize(@"加载器服务器返回 HTTP %ld。", nil),
                        (long)http.statusCode]}];
        }
        NSError *moveError = nil;
        if (location && !error) {
            [NSFileManager.defaultManager removeItemAtPath:target error:nil];
            [NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:target] error:&moveError];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.loaderInstallTask != task) return;
            weakSelf.loaderInstallTask = nil;
            weakSelf.activeDownloadIdentifier = nil;
            weakSelf.activeTaskRequiresDownload = NO;
            if (error || moveError) {
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                [weakSelf postTaskActive:NO];
                showDialog(localize(@"加载器安装失败", nil), error.localizedDescription ?: moveError.localizedDescription);
                return;
            }
            [weakSelf presentPendingLoaderInstallerAtPath:target loader:loader
                minecraftVersion:minecraftVersion loaderVersion:loaderVersion];
        });
    }];
    self.loaderInstallTask = task;
    self.launchTaskPhase = localize(@"正在下载模组加载器…", nil);
    [self postTaskActive:YES];
    [task resume];
}

- (void)launchMinecraft:(UIButton *)sender {
    if (!self.versionTextField.hasText) {
        [self.versionTextField becomeFirstResponder];
        return;
    }

    if (BaseAuthenticator.current == nil) {
        // Present the account selector if none selected
        UIViewController *view = [(UINavigationController *)self.splitViewController.viewControllers[0]
        viewControllers][0];
        [view performSelector:@selector(selectAccount:) withObject:sender];
        return;
    }

    NSMutableDictionary *selectedProfile = PLProfiles.current.selectedProfile;
    NSDictionary *pendingModpack = [selectedProfile[@"pocketjPendingModpack"]
        isKindOfClass:NSDictionary.class]
        ? (NSDictionary *)selectedProfile[@"pocketjPendingModpack"] : nil;
    if (pendingModpack) {
        [self downloadPendingModpack:pendingModpack];
        return;
    }
    if ([selectedProfile[@"pocketjLoaderInstallPending"] boolValue]) {
        [self installPendingLoaderForProfile:selectedProfile sender:sender];
        return;
    }

    // One tap owns the complete launch pipeline. Resource preparation runs
    // first; when it finishes, invokeAfterJITEnabled enables JIT if needed and
    // immediately continues into the Minecraft surface.
    self.deferGameLaunchAfterJITEnable = !isJITEnabled(false);

    [self setInteractionEnabled:NO forDownloading:YES];

    NSString *versionId = PLProfiles.current.profiles[self.versionTextField.text][@"lastVersionId"];
    NSDictionary *object = [remoteVersionList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(id == %@)", versionId]].firstObject;
    if (!object) {
        object = @{
            @"id": versionId,
            @"type": @"custom"
        };
    }

    self.task = [MinecraftResourceDownloadTask new];
    self.downloadPlanResolved = NO;
    BOOL checksIntegrity = getPrefBool(@"general.check_sha");
    self.launchTaskPhase = checksIntegrity
        ? localize(@"正在检查完整性…", nil)
        : localize(@"正在读取本地游戏文件…", nil);
    self.currentTaskPaused = NO;
    self.activeDownloadIdentifier = self.selectedDownloadIdentifier;
    self.activeTaskRequiresDownload =
        [self selectedProfileNeedsDownload];
    MinecraftResourceDownloadTask *downloadTask = self.task;
    if (self.activeTaskRequiresDownload) {
        [self markSelectedDownloadInterrupted];
    } else {
        [self clearSelectedDownloadInterrupted];
    }
    __weak typeof(self) weakSelf = self;
    downloadTask.downloadPlanReady = ^(BOOL needsDownload) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.task != downloadTask) return;
            weakSelf.activeTaskRequiresDownload = needsDownload;
            weakSelf.downloadPlanResolved = YES;
            weakSelf.launchTaskPhase = needsDownload
                ? localize(@"正在下载 Minecraft…", nil)
                : (checksIntegrity ? localize(@"完整性检查完成", nil)
                                   : localize(@"本地游戏文件已就绪", nil));
            if (needsDownload) {
                [weakSelf markSelectedDownloadInterrupted];
            } else {
                [weakSelf setDownloadState:YES
                                identifier:weakSelf.activeDownloadIdentifier
                                       key:LauncherVerifiedCompletesKey];
                [weakSelf clearSelectedDownloadInterrupted];
            }
            // Refresh pause/details visibility from the kernel's actual plan.
            [weakSelf postTaskActive:YES];
        });
    };
    [self postTaskActive:YES];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        downloadTask.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.task != downloadTask) {
                    return;
                }
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                weakSelf.task = nil;
                weakSelf.currentTaskPaused = NO;
                if (!weakSelf.activeTaskRequiresDownload) {
                    [weakSelf clearSelectedDownloadInterrupted];
                }
                weakSelf.activeTaskRequiresDownload = NO;
                weakSelf.activeDownloadIdentifier = nil;
                weakSelf.progressVC = nil;
                [weakSelf postTaskActive:NO];
            });
        };
        [downloadTask downloadVersion:object];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.task != downloadTask || downloadTask.progress.cancelled) {
                return;
            }
            self.progressViewMain.observedProgress = downloadTask.progress;
            [downloadTask.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];
        });
    });
}

- (void)downloadPendingModpack:(NSDictionary *)pending {
    if (self.task) return;
    NSString *source = pending[@"source"];
    ModpackAPI *api = [source isEqualToString:@"modrinth"]
        ? [ModrinthAPI new] : nil;
    NSDictionary *detail = [pending[@"detail"] isKindOfClass:NSDictionary.class]
        ? pending[@"detail"] : nil;
    if (!api || !detail) {
        showDialog(localize(@"整合包配置无效", nil),
            localize(@"请删除该待下载项后重新从在线整合包添加。", nil));
        return;
    }
    [self setInteractionEnabled:NO forDownloading:YES];
    self.task = [MinecraftResourceDownloadTask new];
    self.downloadPlanResolved = YES;
    self.launchTaskPhase = localize(@"正在下载并解析整合包…", nil);
    self.currentTaskPaused = NO;
    self.activeDownloadIdentifier = self.selectedDownloadIdentifier;
    self.activeTaskRequiresDownload = YES;
    [self markSelectedDownloadInterrupted];
    [self postTaskActive:YES];
    MinecraftResourceDownloadTask *downloadTask = self.task;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        downloadTask.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.task != downloadTask) return;
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                weakSelf.task = nil;
                weakSelf.currentTaskPaused = NO;
                weakSelf.activeTaskRequiresDownload = NO;
                weakSelf.activeDownloadIdentifier = nil;
                weakSelf.progressVC = nil;
                [weakSelf postTaskActive:NO];
            });
        };
        [downloadTask downloadModpackFromAPI:api detail:detail atIndex:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.task != downloadTask || downloadTask.progress.cancelled) return;
            weakSelf.progressViewMain.observedProgress = downloadTask.progress;
            [downloadTask.progress addObserver:weakSelf
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];
        });
    });
}

- (void)performInstallOrShowDetails:(id)sender {
    BOOL usesBarButtonItem = [sender isKindOfClass:UIBarButtonItem.class];
    if (self.task && !self.hasActiveLaunchTask) {
        // The selected instance changed outside the launch page. A task may
        // never be reused for another instance, even when both profiles happen
        // to have the same name.
        [self cancelCurrentLaunchTask];
    }
    if (self.task) {
        if (!self.progressVC) {
            UIViewController *vc = [[DownloadProgressViewController alloc] initWithTask:self.task];
            self.progressVC = [[UINavigationController alloc] initWithRootViewController:vc];
        } else if (self.progressVC.popoverPresentationController._isDismissing) {
            // FIXME: stock bug? it crashes when users dismisses and presents this vc too fast
            // "UIPopoverPresentationController () should have a non-nil sourceView or barButtonItem set before the presentation occurs."
            return;
        }

        if (self.traitCollection.horizontalSizeClass ==
                UIUserInterfaceSizeClassRegular) {
            // Preserve the compact anchored popover on genuinely wide layouts.
            self.progressVC.modalPresentationStyle =
                UIModalPresentationPopover;
            if (usesBarButtonItem) {
                self.progressVC.popoverPresentationController.barButtonItem =
                    sender;
            } else {
                self.progressVC.popoverPresentationController.sourceView =
                    sender;
                self.progressVC.popoverPresentationController.sourceRect =
                    ((UIView *)sender).bounds;
            }
        } else {
            // Compact-width iPhones use the stock half-height sheet. iOS 14
            // falls back to its native page sheet because detents start at 15.
            self.progressVC.modalPresentationStyle =
                UIModalPresentationPageSheet;
            self.progressVC.preferredContentSize =
                CGSizeMake(self.view.bounds.size.width, 440);
            if (@available(iOS 15.0, *)) {
                UISheetPresentationController *sheet =
                    self.progressVC.sheetPresentationController;
                sheet.detents = @[
                    UISheetPresentationControllerDetent.mediumDetent
                ];
                sheet.selectedDetentIdentifier =
                    UISheetPresentationControllerDetentIdentifierMedium;
                sheet.prefersGrabberVisible = YES;
                sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
            }
        }
        [self presentViewController:self.progressVC animated:YES completion:nil];
    } else {
        if (usesBarButtonItem) {
            sender = ((UIBarButtonItem *)sender).buttonGlassView;
        }
        [self launchMinecraft:sender];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != ProgressObserverContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // Calculate download speed and ETA
    static CGFloat lastMsTime;
    static NSUInteger lastSecTime, lastCompletedUnitCount;
    NSProgress *progress = self.task.textProgress;
    struct timeval tv;
    gettimeofday(&tv, NULL); 
    NSInteger completedUnitCount = self.task.progress.totalUnitCount * self.task.progress.fractionCompleted;
    progress.completedUnitCount = completedUnitCount;
    if (lastSecTime < tv.tv_sec) {
        CGFloat currentTime = tv.tv_sec + tv.tv_usec / 1000000.0;
        NSInteger throughput = (completedUnitCount - lastCompletedUnitCount) / (currentTime - lastMsTime);
        progress.throughput = @(throughput);
        progress.estimatedTimeRemaining = @((progress.totalUnitCount - completedUnitCount) / throughput);
        lastCompletedUnitCount = completedUnitCount;
        lastSecTime = tv.tv_sec;
        lastMsTime = currentTime;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressText.text = progress.localizedAdditionalDescription;

        if (self.currentTaskPaused) {
            self.launchTaskPhase = localize(@"下载已暂停", nil);
        } else if (self.activeTaskRequiresDownload) {
            NSInteger percent = (NSInteger)llround(progress.fractionCompleted * 100.0);
            self.launchTaskPhase = [self phaseForDownloadTask:self.task
                percent:MAX(0, MIN(percent, 100))];
        }
        [self postTaskActive:YES];

        if (!progress.finished) return;
        [self.progressVC dismissModalViewControllerAnimated:NO];

        self.progressViewMain.observedProgress = nil;
        NSDictionary *metadata = self.task.metadata;
        NSMutableDictionary *completedProfile = nil;
        BOOL continueWithLoaderInstall = NO;
        if (!metadata) {
            NSMutableDictionary *profile = PLProfiles.current.selectedProfile;
            if ([profile[@"pocketjPendingModpack"] isKindOfClass:NSDictionary.class]) {
                [profile removeObjectForKey:@"pocketjPendingModpack"];
                [PLProfiles.current save];
                completedProfile = profile;
                continueWithLoaderInstall = [profile[@"pocketjLoaderInstallPending"] boolValue];
            }
            [self reloadProfileList];
        }
        self.task = nil;
        self.currentTaskPaused = NO;
        self.activeTaskRequiresDownload = NO;
        [self clearSelectedDownloadInterrupted];
        self.activeDownloadIdentifier = nil;
        [self setInteractionEnabled:YES forDownloading:YES];
        [self postTaskActive:NO];
        if (metadata) {
            NSMutableDictionary *profile = PLProfiles.current.selectedProfile;
            profile[@"pocketjResourcesVerified"] = @YES;
            [PLProfiles.current save];
            [self setDownloadState:YES identifier:self.selectedDownloadIdentifier
                key:LauncherVerifiedCompletesKey];
            [self invokeAfterJITEnabled:^{
                UIKit_launchMinecraftSurfaceVC(self.view.window, metadata);
            }];
        } else if (continueWithLoaderInstall && completedProfile) {
            // Modpack acquisition and loader installation are separate stages.
            // The package/dependencies stay cached, so retrying after an
            // installer failure starts here instead of downloading them again.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self installPendingLoaderForProfile:completedProfile sender:nil];
            });
        }
    });
}

- (void)receiveNotification:(NSNotification *)notification {
    if (![notification.name isEqualToString:@"InstallModpack"]) {
        return;
    }
    NSDictionary *userInfo = notification.userInfo;
    NSDictionary *detail = userInfo[@"detail"];
    NSUInteger index = [userInfo[@"index"] unsignedLongValue];
    NSArray *urls = detail[@"versionUrls"];
    if (![detail isKindOfClass:NSDictionary.class] || index >= urls.count) {
        showDialog(localize(@"整合包配置无效", nil),
            localize(@"所选版本没有可用的下载文件。", nil));
        return;
    }

    NSString *baseName = [detail[@"title"] isKindOfClass:NSString.class]
        ? detail[@"title"] : localize(@"在线整合包", nil);
    baseName = [baseName stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!baseName.length) baseName = localize(@"在线整合包", nil);

    // A modpack is a standalone instance. Never register it in the currently
    // selected instance's launcher_profiles.json.
    NSString *instancesRoot = [NSString stringWithFormat:@"%s/instances", getenv("POJAV_HOME")];
    NSString *safeBaseName = [[baseName stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
        stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *directoryName = safeBaseName;
    NSUInteger suffix = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:
        [instancesRoot stringByAppendingPathComponent:directoryName]]) {
        directoryName = [NSString stringWithFormat:@"%@ %lu", safeBaseName,
            (unsigned long)suffix++];
    }
    NSString *instancePath = [instancesRoot stringByAppendingPathComponent:directoryName];
    NSError *directoryError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:instancePath
        withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        showDialog(localize(@"无法创建实例", nil), directoryError.localizedDescription);
        return;
    }
    NSString *profileName = baseName;

    id (^valueAt)(NSString *) = ^id(NSString *key) {
        NSArray *values = [detail[key] isKindOfClass:NSArray.class] ? detail[key] : @[];
        return index < values.count ? values[index] : @"";
    };
    NSDictionary *selectedDetail = @{
        @"apiSource": detail[@"apiSource"] ?: @1,
        @"id": detail[@"id"] ?: @"",
        @"title": baseName,
        @"versionNames": @[valueAt(@"versionNames") ?: @""],
        @"mcVersionNames": @[valueAt(@"mcVersionNames") ?: @""],
        @"versionSizes": @[valueAt(@"versionSizes") ?: @0],
        @"versionUrls": @[valueAt(@"versionUrls") ?: @""],
        @"versionHashes": @[valueAt(@"versionHashes") ?: @""]
    };
    NSString *minecraftVersion = valueAt(@"mcVersionNames");
    NSMutableDictionary *profile = [@{
        @"name": profileName,
        @"lastVersionId": minecraftVersion.length ? minecraftVersion : @"latest-release",
        @"gameDir": @".",
        @"pocketjMinecraftVersion": minecraftVersion ?: @"",
        @"pocketjPendingModpack": @{
            @"source": @"modrinth",
            @"detail": selectedDetail
        }
    } mutableCopy];
    NSDictionary *profileDatabase = @{
        @"profiles": @{profileName: profile},
        @"selectedProfile": profileName
    };
    NSError *saveError = saveJSONToFile(profileDatabase,
        [instancePath stringByAppendingPathComponent:@"launcher_profiles.json"]);
    if (saveError) {
        showDialog(localize(@"无法创建实例", nil), saveError.localizedDescription);
        return;
    }
    [self reloadProfileList];
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"LauncherProfilesDidChangeNotification" object:nil];
    showDialog(localize(@"已添加整合包", nil),
        localize(@"已登记为待下载实例，请回到启动页统一下载。", nil));
}

- (void)invokeAfterJITEnabled:(void(^)(void))handler {
    localVersionList = remoteVersionList = nil;
    BOOL hasTrollStoreJIT = getEntitlementValue(@"jb.pmap_cs.custom_trust");
    BOOL isLiveContainer = getenv("LC_HOME_PATH") != NULL;

    if (isJITEnabled(false)) {
        self.deferGameLaunchAfterJITEnable = NO;
        [ALTServerManager.sharedManager stopDiscovering];
        handler();
        return;
    } else if (@available(iOS 26.0, *)) {
        if (StikDebugEngine.sharedEngine.hasPairingFile) {
            self.jitEnabling = YES;
            self.activeDownloadIdentifier = self.selectedDownloadIdentifier;
            self.launchTaskPhase = localize(@"正在开启 JIT…", nil);
            self.progressText.text = localize(@"正在开启内置 JIT…", nil);
            [self postTaskActive:YES];
            [StikDebugViewController enableEmbeddedJITWithCompletion:
                ^(BOOL success, NSString *message) {
                    if (success || isJITEnabled(false)) {
                        if (self.deferGameLaunchAfterJITEnable) {
                            [self showJITReadyFeedbackThen:handler];
                        } else {
                            self.jitEnabling = NO;
                            self.activeDownloadIdentifier = nil;
                            [self postTaskActive:NO];
                            handler();
                        }
                    } else {
                        self.jitEnabling = NO;
                        self.launchTaskPhase = nil;
                        self.activeDownloadIdentifier = nil;
                        [self postTaskActive:NO];
                        self.deferGameLaunchAfterJITEnable = NO;
                        NSString *detail = message.length ? message : localize(@"未知错误", nil);
                        if ([detail localizedCaseInsensitiveContainsString:@"Timed out connecting"] ||
                            [detail localizedCaseInsensitiveContainsString:@"not ready for JIT"]) {
                            detail = [detail stringByAppendingFormat:@"\n\n%@",
                                localize(@"请确保 LocalDevVPN 已开启后重试。", nil)];
                        }
                        showDialog(localize(@"无法开启 JIT", nil), detail);
                    }
                }];
            return;
        }
        ModernRootTabBarController *root =
            [self.tabBarController isKindOfClass:ModernRootTabBarController.class]
                ? (ModernRootTabBarController *)self.tabBarController : nil;
        if (root) {
            [root openJITSettingsWithConfigurationPrompt:YES];
        } else {
            [self pushViewController:[StikDebugViewController new] animated:YES];
            showDialog(localize(@"JIT 等待配置", nil),
                localize(@"开始游戏前，请先导入本机配对文件并开启 LocalDevVPN。", nil));
        }
        return;
    } else if (hasTrollStoreJIT) {
        NSURL *jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", NSBundle.mainBundle.bundleIdentifier]];
        [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:nil];
        // Do not return, wait for TrollStore to enable JIT and jump back
    } else if (getPrefBool(@"debug.debug_skip_wait_jit")) {
        NSLog(@"Debug option skipped waiting for JIT. Java might not work.");
        handler();
        return;
    } else if (@available(iOS 17.4, *)) {
        NSURLComponents *components = [[NSURLComponents alloc] init];
        components.scheme = @"stikjit";
        components.host = @"enable-jit";
        NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithObject:
            [NSURLQueryItem queryItemWithName:@"bundle-id"
                                        value:NSBundle.mainBundle.bundleIdentifier]];
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"pid"
                                                          value:[NSString stringWithFormat:@"%d", getpid()]]];
        if(DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
            NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
            if (scriptData.length > 0) {
                [queryItems addObject:[NSURLQueryItem queryItemWithName:@"script-data"
                                                                value:[scriptData base64EncodedStringWithOptions:0]]];
                [queryItems addObject:[NSURLQueryItem queryItemWithName:@"script-name"
                                                                value:@"UniversalJIT26.js"]];
            }
        }
        components.queryItems = queryItems;
        NSURL *jitURL = components.URL;
        if (jitURL) {
            // Attach to the existing process. Asking StikDebug to launch an app
            // that is already running can terminate this process and start a new
            // one, losing the in-flight launch request and producing a flash/crash.
            [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:^(BOOL success) {
                NSLog(@"StikDebug JIT request %@: %@", success ? @"opened" : @"failed", jitURL.absoluteString);
            }];
        }
    } else {
        // Assuming 16.7-17.3.1. SideStore still lacks this URL scheme at the time of writing, so it only jumps to SideStore.
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]] options:@{} completionHandler:nil];
    }

    self.progressText.text = localize(@"launcher.wait_jit.title", nil);
    self.jitEnabling = YES;
    self.activeDownloadIdentifier = self.selectedDownloadIdentifier;
    [self postTaskActive:YES];

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"launcher.wait_jit.title", nil)
        message:hasTrollStoreJIT ? localize(@"launcher.wait_jit_trollstore.message", nil) : localize(@"launcher.wait_jit.message", nil)
        preferredStyle:UIAlertControllerStyleAlert];
/* TODO:
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^{
        
    }];
    [alert addAction:cancel];
*/
    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (!isJITEnabled(false)) {
            // Perform check for every 200ms
            usleep(1000*200);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                if (self.deferGameLaunchAfterJITEnable) {
                    [self showJITReadyFeedbackThen:handler];
                } else {
                    self.jitEnabling = NO;
                    self.activeDownloadIdentifier = nil;
                    [self postTaskActive:NO];
                    handler();
                }
            }];
        });
    });
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - UIPickerView stuff
- (void)pickerView:(PLPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    self.profileSelectedAt = row;
    //((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    ((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
    PLProfiles.current.selectedProfileName = self.versionTextField.text;
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return PLProfiles.current.profiles.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return PLProfiles.current.profiles.allValues[row][@"name"];
}

- (void)pickerView:(UIPickerView *)pickerView enumerateImageView:(UIImageView *)imageView forRow:(NSInteger)row forComponent:(NSInteger)component {
    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(40, 40)];
    NSString *urlString = PLProfiles.current.profiles.allValues[row][@"icon"];
    [imageView setImageWithURL:[NSURL URLWithString:urlString] placeholderImage:fallbackImage];
}

- (void)versionClosePicker {
    [self.versionTextField endEditing:YES];
    [self pickerView:self.versionPickerView didSelectRow:[self.versionPickerView selectedRowInComponent:0] inComponent:0];
}

#pragma mark - View controller UI mode

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [sidebarViewController updateAccountInfo];
    if (self.globalToolbarItems &&
        ![self.splitViewController isKindOfClass:NSClassFromString(@"ModernLauncherViewController")]) {
        if (!self.viewControllers.firstObject.toolbarItems) {
            self.viewControllers.firstObject.toolbarItems = self.globalToolbarItems;
        }
        // resize textFieldContainer to fit, need dispatch queue or it freezes for some reason...
        dispatch_async(dispatch_get_main_queue(), ^{
            self.versionTextField.superview.frame = CGRectMake(0, 0, MIN(self.view.frame.size.width,self.view.frame.size.height)*0.8 - 40, 36);
        });
    }
}

@end
