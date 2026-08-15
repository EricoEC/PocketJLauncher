#import "ModernLaunchViewController.h"

#import "AccountListViewController.h"
#import "authenticator/BaseAuthenticator.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "ModernUITheme.h"
#import "PLProfiles.h"
#import "utils.h"

@interface ModernLaunchViewController ()
@property(nonatomic) UILabel *selectedProfileLabel;
@property(nonatomic) UILabel *selectedVersionLabel;
@property(nonatomic) UILabel *selectedAccountLabel;
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) UIButton *playButton;
@property(nonatomic) UIButton *pauseButton;
@property(nonatomic) UIButton *detailsButton;
@property(nonatomic) UIStackView *taskActions;
@property(nonatomic) UIProgressView *progressView;
@property(nonatomic) BOOL launchRunning;
@property(nonatomic) BOOL launchPaused;
@property(nonatomic) BOOL hasSelectedInstance;
@property(nonatomic) BOOL hasConfiguredVersion;
@property(nonatomic) BOOL directLaunchWithoutDownload;
@end

@implementation ModernLaunchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"启动", nil);
    [ModernUITheme styleController:self];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self buildV03Interface];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(launchTaskStateDidChange:)
               name:LauncherTaskStateDidChangeNotification
             object:nil];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(savedProfileDidChange:)
               name:@"LauncherProfilesDidChangeNotification"
             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    LauncherNavigationController *navigation = (id)self.navigationController;
    if ([navigation respondsToSelector:@selector(reloadProfileList)]) {
        [navigation performSelector:@selector(reloadProfileList)];
    }
    [self setLaunchRunning:navigation.hasActiveLaunchTask];
    [self setLaunchPaused:navigation.isCurrentLaunchTaskPaused];
    [self reloadContent];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)savedProfileDidChange:(NSNotification *)notification {
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    if ([navigation respondsToSelector:@selector(reloadProfileList)]) {
        [navigation performSelector:@selector(reloadProfileList)];
    }
    [self reloadContent];
}

- (UILabel *)label:(NSString *)text style:(UIFontTextStyle)style {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    return label;
}

- (void)buildV03Interface {
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIView *glow = [UIView new];
    glow.translatesAutoresizingMaskIntoConstraints = NO;
    glow.userInteractionEnabled = NO;
    glow.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.14];
    glow.layer.cornerRadius = 190;
    glow.layer.shadowColor = UIColor.systemGreenColor.CGColor;
    glow.layer.shadowOpacity = 0.24;
    glow.layer.shadowRadius = 85;
    glow.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:glow];

    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIStackView *content = [UIStackView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 18;
    content.layoutMargins = UIEdgeInsetsMake(14, 18, 44, 18);
    content.layoutMarginsRelativeArrangement = YES;
    [scrollView addSubview:content];

    UIVisualEffectView *hero = [ModernUITheme glassViewWithCornerRadius:28 interactive:YES];
    hero.contentView.layoutMargins = UIEdgeInsetsMake(22, 22, 22, 22);
    [content addArrangedSubview:hero];

    UIStackView *heroStack = [UIStackView new];
    heroStack.translatesAutoresizingMaskIntoConstraints = NO;
    heroStack.axis = UILayoutConstraintAxisVertical;
    heroStack.spacing = 14;
    [hero.contentView addSubview:heroStack];

    UIStackView *heroHeader = [UIStackView new];
    heroHeader.axis = UILayoutConstraintAxisHorizontal;
    heroHeader.alignment = UIStackViewAlignmentTop;
    heroHeader.spacing = 12;
    [heroStack addArrangedSubview:heroHeader];

    UIStackView *heading = [UIStackView new];
    heading.axis = UILayoutConstraintAxisVertical;
    heading.spacing = 5;
    [heroHeader addArrangedSubview:heading];

    UILabel *minecraft = [self label:@"MINECRAFT" style:UIFontTextStyleCaption1];
    minecraft.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    minecraft.textColor = UIColor.systemGreenColor;
    [heading addArrangedSubview:minecraft];

    UILabel *javaEdition = [self label:@"Java Edition" style:UIFontTextStyleLargeTitle];
    javaEdition.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [heading addArrangedSubview:javaEdition];

    UIView *spacer = [UIView new];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [heroHeader addArrangedSubview:spacer];

    UIVisualEffectView *cubeGlass = [ModernUITheme glassViewWithCornerRadius:18 interactive:NO];
    [heroHeader addArrangedSubview:cubeGlass];
    UIImageView *cube = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cube.fill"]];
    cube.translatesAutoresizingMaskIntoConstraints = NO;
    cube.tintColor = UIColor.systemGreenColor;
    cube.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightSemibold];
    [cubeGlass.contentView addSubview:cube];

    self.selectedProfileLabel = [self label:localize(@"请选择一个游戏版本", nil) style:UIFontTextStyleSubheadline];
    self.selectedProfileLabel.textColor = UIColor.secondaryLabelColor;
    [heroStack addArrangedSubview:self.selectedProfileLabel];

    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventPrimaryActionTriggered];
    if (@available(iOS 15.0, *)) {
        self.playButton.configuration =
            [ModernUITheme primaryButtonConfigurationWithTitle:localize(@"开始游戏", nil)
                                                         image:[UIImage systemImageNamed:@"play.fill"]];
    } else {
        [self.playButton setTitle:localize(@"开始游戏", nil) forState:UIControlStateNormal];
        [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        self.playButton.tintColor = UIColor.whiteColor;
        self.playButton.backgroundColor = UIColor.systemGreenColor;
        self.playButton.layer.cornerRadius = 17;
    }
    [ModernUITheme styleContinuousButton:self.playButton cornerRadius:20];
    [self.playButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [heroStack addArrangedSubview:self.playButton];

    self.taskActions = [UIStackView new];
    self.taskActions.axis = UILayoutConstraintAxisHorizontal;
    self.taskActions.distribution = UIStackViewDistributionFillEqually;
    self.taskActions.spacing = 10;
    self.taskActions.hidden = YES;
    [heroStack addArrangedSubview:self.taskActions];

    self.pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pauseButton addTarget:self
                         action:@selector(togglePause)
               forControlEvents:UIControlEventPrimaryActionTriggered];
    self.detailsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.detailsButton addTarget:self
                           action:@selector(showDownloadDetails)
                 forControlEvents:UIControlEventPrimaryActionTriggered];
    if (@available(iOS 15.0, *)) {
        self.pauseButton.configuration =
            [ModernUITheme actionButtonConfigurationWithTitle:localize(@"暂停", nil)
                image:[UIImage systemImageNamed:@"pause.fill"]
                tint:UIColor.systemOrangeColor
                prominent:NO];
        self.detailsButton.configuration =
            [ModernUITheme actionButtonConfigurationWithTitle:localize(@"下载进度", nil)
                image:[UIImage systemImageNamed:@"list.bullet.rectangle"]
                tint:UIColor.systemBlueColor
                prominent:NO];
    } else {
        [self.pauseButton setTitle:localize(@"暂停", nil)
                          forState:UIControlStateNormal];
        [self.pauseButton setImage:[UIImage systemImageNamed:@"pause.fill"]
                         forState:UIControlStateNormal];
        [self.detailsButton setTitle:localize(@"下载进度", nil)
                            forState:UIControlStateNormal];
        [self.detailsButton
            setImage:[UIImage systemImageNamed:@"list.bullet.rectangle"]
            forState:UIControlStateNormal];
        self.pauseButton.backgroundColor = UIColor.secondarySystemFillColor;
        self.detailsButton.backgroundColor = UIColor.secondarySystemFillColor;
    }
    [ModernUITheme styleContinuousButton:self.pauseButton cornerRadius:17];
    [ModernUITheme styleContinuousButton:self.detailsButton cornerRadius:17];
    [self.pauseButton.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.detailsButton.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.taskActions addArrangedSubview:self.pauseButton];
    [self.taskActions addArrangedSubview:self.detailsButton];

    UIVisualEffectView *selectionCard =
        [ModernUITheme glassViewWithCornerRadius:22 interactive:YES];
    [content addArrangedSubview:selectionCard];

    UIStackView *selectionStack = [UIStackView new];
    selectionStack.translatesAutoresizingMaskIntoConstraints = NO;
    selectionStack.axis = UILayoutConstraintAxisVertical;
    selectionStack.spacing = 0;
    [selectionCard.contentView addSubview:selectionStack];

    UIButton *profileRow = [self selectionRowWithIcon:@"square.stack.3d.up.fill"
                                                title:localize(@"游戏实例", nil)
                                               action:@selector(openProfilePicker:)];
    self.selectedVersionLabel = [profileRow viewWithTag:7202];
    [selectionStack addArrangedSubview:profileRow];

    UIView *divider = [UIView new];
    divider.backgroundColor = UIColor.separatorColor;
    [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [selectionStack addArrangedSubview:divider];

    UIButton *accountRow = [self selectionRowWithIcon:@"person.crop.circle.fill"
                                                title:localize(@"当前账户", nil)
                                               action:@selector(openAccountsTab)];
    self.selectedAccountLabel = [accountRow viewWithTag:7202];
    [selectionStack addArrangedSubview:accountRow];

    UIStackView *status = [UIStackView new];
    status.axis = UILayoutConstraintAxisVertical;
    status.spacing = 8;
    [content addArrangedSubview:status];

    UIStackView *statusRow = [UIStackView new];
    statusRow.axis = UILayoutConstraintAxisHorizontal;
    statusRow.alignment = UIStackViewAlignmentCenter;
    statusRow.spacing = 8;
    [status addArrangedSubview:statusRow];
    UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    check.tintColor = UIColor.secondaryLabelColor;
    [check.widthAnchor constraintEqualToConstant:20].active = YES;
    [check.heightAnchor constraintEqualToConstant:20].active = YES;
    [statusRow addArrangedSubview:check];
    self.statusLabel = [self label:localize(@"准备就绪", nil) style:UIFontTextStyleSubheadline];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [statusRow addArrangedSubview:self.statusLabel];

    self.progressView = [UIProgressView new];
    self.progressView.progressTintColor = UIColor.systemGreenColor;
    self.progressView.hidden = YES;
    [status addArrangedSubview:self.progressView];

    UIImage *homeBrandImage = [UIImage imageNamed:@"PocketJHomeBrand"];
    if (homeBrandImage) {
        UIImageView *homeBrandView = [[UIImageView alloc] initWithImage:homeBrandImage];
        homeBrandView.translatesAutoresizingMaskIntoConstraints = NO;
        homeBrandView.contentMode = UIViewContentModeScaleAspectFit;
        homeBrandView.clipsToBounds = YES;
        homeBrandView.isAccessibilityElement = YES;
        homeBrandView.accessibilityLabel = @"PocketJ Launcher";
        [content addArrangedSubview:homeBrandView];

        CGFloat aspectRatio = homeBrandImage.size.height / MAX(homeBrandImage.size.width, 1.0);
        NSLayoutConstraint *aspectConstraint =
            [homeBrandView.heightAnchor constraintEqualToAnchor:homeBrandView.widthAnchor
                                                     multiplier:aspectRatio];
        aspectConstraint.priority = UILayoutPriorityDefaultHigh;
        aspectConstraint.active = YES;
        [homeBrandView.heightAnchor constraintLessThanOrEqualToConstant:180.0].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [glow.widthAnchor constraintEqualToConstant:380],
        [glow.heightAnchor constraintEqualToConstant:380],
        [glow.centerXAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [glow.centerYAnchor constraintEqualToAnchor:self.view.topAnchor constant:-40],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
        [heroStack.leadingAnchor constraintEqualToAnchor:hero.contentView.layoutMarginsGuide.leadingAnchor],
        [heroStack.trailingAnchor constraintEqualToAnchor:hero.contentView.layoutMarginsGuide.trailingAnchor],
        [heroStack.topAnchor constraintEqualToAnchor:hero.contentView.layoutMarginsGuide.topAnchor],
        [heroStack.bottomAnchor constraintEqualToAnchor:hero.contentView.layoutMarginsGuide.bottomAnchor],
        [cubeGlass.widthAnchor constraintEqualToConstant:60],
        [cubeGlass.heightAnchor constraintEqualToConstant:60],
        [cube.centerXAnchor constraintEqualToAnchor:cubeGlass.contentView.centerXAnchor],
        [cube.centerYAnchor constraintEqualToAnchor:cubeGlass.contentView.centerYAnchor],
        [selectionStack.leadingAnchor constraintEqualToAnchor:selectionCard.contentView.leadingAnchor],
        [selectionStack.trailingAnchor constraintEqualToAnchor:selectionCard.contentView.trailingAnchor],
        [selectionStack.topAnchor constraintEqualToAnchor:selectionCard.contentView.topAnchor constant:4],
        [selectionStack.bottomAnchor constraintEqualToAnchor:selectionCard.contentView.bottomAnchor constant:-4],
    ]];
}

- (UIButton *)selectionRowWithIcon:(NSString *)icon
                             title:(NSString *)title
                            action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;

    UIStackView *row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.userInteractionEnabled = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 13;
    [button addSubview:row];

    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    image.tintColor = UIColor.systemGreenColor;
    [image.widthAnchor constraintEqualToConstant:32].active = YES;
    [image.heightAnchor constraintEqualToConstant:32].active = YES;
    [row addArrangedSubview:image];

    UIStackView *labels = [UIStackView new];
    labels.axis = UILayoutConstraintAxisVertical;
    labels.spacing = 2;
    [row addArrangedSubview:labels];
    UILabel *titleLabel = [self label:title style:UIFontTextStyleSubheadline];
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [labels addArrangedSubview:titleLabel];
    UILabel *valueLabel = [self label:@"—" style:UIFontTextStyleCaption1];
    valueLabel.tag = 7202;
    valueLabel.textColor = UIColor.secondaryLabelColor;
    [labels addArrangedSubview:valueLabel];

    UIView *spacer = [UIView new];
    [row addArrangedSubview:spacer];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor = UIColor.secondaryLabelColor;
    [row addArrangedSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:62],
        [row.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:button.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
    ]];
    return button;
}

- (NSString *)loaderForVersion:(NSString *)version {
    NSString *lower = version.lowercaseString ?: @"";
    if ([lower containsString:@"neoforge"]) return @"NeoForge";
    if ([lower containsString:@"fabric"]) return @"Fabric";
    if ([lower containsString:@"quilt"]) return @"Quilt";
    if ([lower containsString:@"forge"]) return @"Forge";
    return @"Vanilla";
}

- (void)reloadContent {
    NSString *instanceName = getPrefObject(@"general.game_directory");
    NSString *instancePath = instanceName.length > 0
        ? [NSString stringWithFormat:@"%s/instances/%@",
            getenv("POJAV_HOME"), instanceName] : nil;
    BOOL isDirectory = NO;
    self.hasSelectedInstance = instancePath.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:instancePath
                                            isDirectory:&isDirectory] &&
        isDirectory;
    if (!self.hasSelectedInstance) {
        self.hasConfiguredVersion = NO;
        self.selectedProfileLabel.text = localize(@"未选择游戏实例", nil);
        self.selectedVersionLabel.text = localize(@"未选择", nil);
        NSString *account = BaseAuthenticator.current.authData[@"username"];
        if (!account.length) {
            account = getPrefObject(@"internal.selected_account");
        }
        self.selectedAccountLabel.text =
            account.length ? account : localize(@"添加离线账户", nil);
        self.statusLabel.text = localize(@"请先创建或导入实例", nil);
        self.playButton.enabled = NO;
        [self updateIdlePlayButton];
        return;
    }

    [PLProfiles updateCurrent];
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    NSString *name = profile[@"name"];
    NSString *version = profile[@"lastVersionId"];
    self.hasConfiguredVersion = version.length > 0;
    NSString *loader = [self loaderForVersion:version];
    self.selectedProfileLabel.text =
        name.length
            ? [NSString stringWithFormat:@"%@ · %@ · %@",
                instanceName, name, loader]
            : localize(@"请选择一个游戏实例", nil);
    self.selectedVersionLabel.text =
        version.length ? [NSString stringWithFormat:@"%@ · %@", version, loader] : localize(@"未选择", nil);
    NSString *account = BaseAuthenticator.current.authData[@"username"];
    if (!account.length) account = getPrefObject(@"internal.selected_account");
    self.selectedAccountLabel.text = account.length ? account : localize(@"添加离线账户", nil);
    self.playButton.enabled =
        self.launchRunning || (name.length > 0 && self.hasConfiguredVersion);
    if (!self.hasConfiguredVersion) {
        self.statusLabel.text =
            localize(@"尚未配置 Minecraft 版本，请在“游戏→实例”中编辑", nil);
    }
    [self updateIdlePlayButton];
}

- (void)openProfilePicker:(UIButton *)sender {
    NSString *instancesRoot =
        [NSString stringWithFormat:@"%s/instances", getenv("POJAV_HOME")];
    NSMutableArray<NSString *> *instanceNames = [NSMutableArray array];
    for (NSString *file in
            [NSFileManager.defaultManager contentsOfDirectoryAtPath:instancesRoot
                                                               error:nil]) {
        BOOL isDirectory = NO;
        NSString *path = [instancesRoot stringByAppendingPathComponent:file];
        if ([NSFileManager.defaultManager fileExistsAtPath:path
                                               isDirectory:&isDirectory] &&
            isDirectory) {
            [instanceNames addObject:file];
        }
    }
    [instanceNames sortUsingSelector:@selector(localizedStandardCompare:)];
    if ([instanceNames containsObject:@"default"]) {
        [instanceNames removeObject:@"default"];
        [instanceNames insertObject:@"default" atIndex:0];
    }

    if (instanceNames.count == 0) {
        UIAlertController *empty =
            [UIAlertController alertControllerWithTitle:localize(@"没有可用的游戏实例", nil)
                                                message:localize(@"请先在“游戏”页面创建一个实例。", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];
        [empty addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];
        __weak typeof(self) weakSelf = self;
        [empty addAction:[UIAlertAction actionWithTitle:localize(@"前往游戏", nil)
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            weakSelf.tabBarController.selectedIndex = 1;
        }]];
        [self presentViewController:empty animated:YES completion:nil];
        return;
    }

    UIAlertController *picker =
        [UIAlertController alertControllerWithTitle:localize(@"选择游戏实例", nil)
                                            message:localize(@"选择本次要启动的独立游戏目录", nil)
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *selectedInstance =
        getPrefObject(@"general.game_directory") ?: @"default";
    __weak typeof(self) weakSelf = self;
    for (NSString *instanceName in instanceNames) {
        NSString *profilesPath = [[instancesRoot
            stringByAppendingPathComponent:instanceName]
            stringByAppendingPathComponent:@"launcher_profiles.json"];
        NSDictionary *profiles = parseJSONFromFile(profilesPath);
        NSString *profileName = profiles[@"selectedProfile"];
        NSDictionary *profile = profiles[@"profiles"][profileName];
        NSString *version = profile[@"lastVersionId"];
        NSString *title = version.length
            ? [NSString stringWithFormat:@"%@ · %@", instanceName, version]
            : instanceName;
        if ([instanceName isEqualToString:selectedInstance]) {
            title = [@"✓ " stringByAppendingString:title];
        }
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            LauncherNavigationController *navigation =
                (LauncherNavigationController *)weakSelf.navigationController;
            // A resource task belongs to the instance that created it. Stop it
            // before moving the game-directory symlink so its paused/download
            // state cannot leak into the newly selected instance.
            if (navigation.hasActiveLaunchTask) {
                [navigation cancelCurrentLaunchTask];
            }
            setPrefObject(@"general.game_directory", instanceName);
            NSString *instancePath =
                [instancesRoot stringByAppendingPathComponent:instanceName];
            NSString *gamePath = @(getenv("POJAV_GAME_DIR"));
            [NSFileManager.defaultManager removeItemAtPath:gamePath error:nil];
            [NSFileManager.defaultManager createSymbolicLinkAtPath:gamePath
                withDestinationPath:instancePath error:nil];
            [NSFileManager.defaultManager
                changeCurrentDirectoryPath:gamePath];
            toggleIsolatedPref(NO);
            [PLProfiles updateCurrent];
            if ([navigation respondsToSelector:@selector(reloadProfileList)]) {
                [navigation performSelector:@selector(reloadProfileList)];
            }
            [weakSelf reloadContent];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    picker.popoverPresentationController.sourceView = sender;
    picker.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openAccountsTab {
    self.tabBarController.selectedIndex = 3;
}

- (void)launchTaskStateDidChange:(NSNotification *)notification {
    if (notification.object != self.navigationController) {
        return;
    }
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    // Notifications from a task attached to another instance must not repaint
    // the currently selected instance as downloading or paused.
    if (!navigation.hasActiveLaunchTask &&
        [notification.userInfo[@"active"] boolValue]) {
        [self setLaunchRunning:NO];
        [self setLaunchPaused:NO];
        [self reloadContent];
        return;
    }
    BOOL active = [notification.userInfo[@"active"] boolValue];
    BOOL paused = [notification.userInfo[@"paused"] boolValue];
    if (active) {
        self.directLaunchWithoutDownload =
            ![notification.userInfo[@"downloading"] boolValue];
    }
    [self setLaunchRunning:active];
    [self setLaunchPaused:paused];
    if (active) {
        self.statusLabel.text =
            paused ? localize(@"下载已暂停", nil) : localize(@"正在准备 Minecraft…", nil);
        self.progressView.hidden = NO;
        self.progressView.progress = 0.05;
    } else {
        BOOL wasStopping =
            [self.statusLabel.text hasPrefix:localize(@"正在停止", nil)];
        self.statusLabel.text = wasStopping ? localize(@"已停止", nil) : localize(@"准备就绪", nil);
        self.progressView.hidden = YES;
        self.progressView.progress = 0;
        [self reloadContent];
    }
}

- (void)setLaunchRunning:(BOOL)running {
    _launchRunning = running;
    UIImage *image =
        [UIImage systemImageNamed:running ? @"stop.fill" : @"play.fill"];
    NSString *title = running ? localize(@"停止运行", nil) : localize(@"开始游戏", nil);
    UIColor *color =
        running ? UIColor.systemRedColor : UIColor.systemGreenColor;

    if (@available(iOS 15.0, *)) {
        self.playButton.configuration =
            [ModernUITheme actionButtonConfigurationWithTitle:title
                image:image
                tint:color
                prominent:YES];
    } else {
        [self.playButton setTitle:title forState:UIControlStateNormal];
        [self.playButton setImage:image forState:UIControlStateNormal];
        self.playButton.tintColor = UIColor.whiteColor;
        self.playButton.backgroundColor = color;
    }
    if (running) {
        self.playButton.enabled = YES;
    }
    self.taskActions.hidden =
        !running || self.directLaunchWithoutDownload;
    if (!running) {
        [self setLaunchPaused:NO];
        [self updateIdlePlayButton];
        self.directLaunchWithoutDownload = NO;
    }
}

- (void)updateIdlePlayButton {
    if (self.launchRunning || !self.playButton) {
        return;
    }
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    if (!self.hasSelectedInstance) {
        NSString *title = localize(@"请先添加实例", nil);
        UIImage *image =
            [UIImage systemImageNamed:@"plus.circle.fill"];
        if (@available(iOS 15.0, *)) {
            self.playButton.configuration =
                [ModernUITheme
                    actionButtonConfigurationWithTitle:title
                    image:image tint:UIColor.systemGrayColor
                    prominent:YES];
        } else {
            [self.playButton setTitle:title
                            forState:UIControlStateNormal];
            [self.playButton setImage:image
                            forState:UIControlStateNormal];
            self.playButton.backgroundColor = UIColor.systemGrayColor;
        }
        self.playButton.enabled = NO;
        return;
    }
    if (!self.hasConfiguredVersion) {
        NSString *title = localize(@"请先配置版本", nil);
        UIImage *image =
            [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        if (@available(iOS 15.0, *)) {
            self.playButton.configuration =
                [ModernUITheme actionButtonConfigurationWithTitle:title
                    image:image tint:UIColor.systemGrayColor
                    prominent:YES];
        } else {
            [self.playButton setTitle:title forState:UIControlStateNormal];
            [self.playButton setImage:image forState:UIControlStateNormal];
            self.playButton.backgroundColor = UIColor.systemGrayColor;
        }
        self.playButton.enabled = NO;
        return;
    }
    BOOL interrupted = navigation.selectedProfileHasInterruptedDownload;
    BOOL needsDownload = navigation.selectedProfileNeedsDownload;
    NSString *title;
    UIColor *color;
    UIImage *image;
    if (interrupted) {
        title = localize(@"继续下载", nil);
        color = UIColor.systemOrangeColor;
        image = [UIImage systemImageNamed:@"arrow.clockwise"];
        self.statusLabel.text = localize(@"下载已中断，可继续", nil);
    } else if (needsDownload) {
        title = localize(@"下载实例", nil);
        color = UIColor.systemBlueColor;
        image = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
    } else {
        title = localize(@"开始游戏", nil);
        color = UIColor.systemGreenColor;
        image = [UIImage systemImageNamed:@"play.fill"];
    }

    if (@available(iOS 15.0, *)) {
        self.playButton.configuration =
            [ModernUITheme actionButtonConfigurationWithTitle:title
                image:image
                tint:color
                prominent:YES];
    } else {
        [self.playButton setTitle:title forState:UIControlStateNormal];
        [self.playButton setImage:image forState:UIControlStateNormal];
        self.playButton.backgroundColor = color;
        self.playButton.tintColor = UIColor.whiteColor;
    }
}

- (void)setLaunchPaused:(BOOL)paused {
    _launchPaused = paused;
    NSString *title = paused ? localize(@"继续", nil) : localize(@"暂停", nil);
    UIImage *image = [UIImage
        systemImageNamed:paused ? @"play.fill" : @"pause.fill"];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration =
            self.pauseButton.configuration;
        configuration.title = title;
        configuration.image = image;
        self.pauseButton.configuration = configuration;
    } else {
        [self.pauseButton setTitle:title forState:UIControlStateNormal];
        [self.pauseButton setImage:image forState:UIControlStateNormal];
    }
}

- (void)togglePause {
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    if (navigation.isCurrentLaunchTaskPaused) {
        [navigation resumeCurrentLaunchTask];
    } else {
        [navigation pauseCurrentLaunchTask];
    }
}

- (void)showDownloadDetails {
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    [navigation performInstallOrShowDetails:self.detailsButton];
}

- (void)togglePlay {
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    if (navigation.hasActiveLaunchTask) {
        self.statusLabel.text = localize(@"正在停止…", nil);
        [navigation cancelCurrentLaunchTask];
        return;
    }
    [self play];
}

- (void)play {
    if (!self.hasSelectedInstance || !self.hasConfiguredVersion) {
        return;
    }
    if (!BaseAuthenticator.current) {
        [self openAccountsTab];
        return;
    }
    self.statusLabel.text = localize(@"正在准备 Minecraft…", nil);
    self.progressView.hidden = NO;
    self.progressView.progress = 0.05;
    LauncherNavigationController *navigation =
        (LauncherNavigationController *)self.navigationController;
    self.directLaunchWithoutDownload =
        !navigation.selectedProfileNeedsDownload &&
        !navigation.selectedProfileHasInterruptedDownload;
    self.taskActions.hidden = self.directLaunchWithoutDownload;
    [navigation
        performSelector:@selector(performInstallOrShowDetails:)
             withObject:self.playButton];
}

@end
