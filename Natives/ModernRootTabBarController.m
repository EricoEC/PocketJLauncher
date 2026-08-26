#import "ModernRootTabBarController.h"

#import "AccountListViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherProfilesViewController.h"
#import "ModernLaunchViewController.h"
#import "ModernSettingsViewController.h"
#import "ModernUITheme.h"
#import "PocketJUpdateChecker.h"
#import "stikdebug/StikDebugViewController.h"
#import "utils.h"

@implementation ModernRootTabBarController

- (void)openJITSettingsWithConfigurationPrompt:(BOOL)showPrompt {
    if (self.viewControllers.count < 5) return;
    self.selectedIndex = 4;
    UINavigationController *settings =
        (UINavigationController *)self.viewControllers[4];
    if (![settings isKindOfClass:UINavigationController.class]) return;

    void (^openPage)(void) = ^{
        UIViewController *top = settings.topViewController;
        if (![top isKindOfClass:StikDebugViewController.class]) {
            [settings pushViewController:[StikDebugViewController new]
                                animated:YES];
        }
    };
    if (!showPrompt) {
        openPage();
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"JIT 等待配置", nil)
        message:localize(@"开始游戏前，请先导入本机配对文件并开启 LocalDevVPN。", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"去配置", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            openPage();
        }]];
    [settings.topViewController presentViewController:alert
                                             animated:YES
                                           completion:nil];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait |
        UIInterfaceOrientationMaskLandscapeLeft |
        UIInterfaceOrientationMaskLandscapeRight;
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return self.selectedViewController;
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.selectedViewController;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [ModernUITheme applyGlobalAppearance];
    // Check once when the launcher UI is created, even if Settings is never opened.
    [PocketJUpdateChecker.shared checkForUpdates];

    LauncherNavigationController *play = [[LauncherNavigationController alloc]
        initWithRootViewController:[ModernLaunchViewController new]];
    play.toolbarHidden = YES;

    UINavigationController *library = [[UINavigationController alloc]
        initWithRootViewController:[LauncherProfilesViewController new]];
    UINavigationController *controls = [[UINavigationController alloc]
        initWithRootViewController:[LauncherPrefContCfgViewController new]];
    UINavigationController *accounts = [[UINavigationController alloc]
        initWithRootViewController:[AccountListViewController new]];
    UINavigationController *settings = [[UINavigationController alloc]
        initWithRootViewController:[ModernSettingsViewController new]];

    play.tabBarItem = [[UITabBarItem alloc] initWithTitle:localize(@"启动", nil)
        image:[UIImage systemImageNamed:@"play.fill"] tag:0];
    library.tabBarItem = [[UITabBarItem alloc] initWithTitle:localize(@"游戏", nil)
        image:[UIImage systemImageNamed:@"square.stack.3d.up.fill"] tag:1];
    controls.tabBarItem = [[UITabBarItem alloc] initWithTitle:localize(@"控制", nil)
        image:[UIImage systemImageNamed:@"gamecontroller.fill"] tag:2];
    accounts.tabBarItem = [[UITabBarItem alloc] initWithTitle:localize(@"账户", nil)
        image:[UIImage systemImageNamed:@"person.crop.circle"] tag:3];
    settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:localize(@"设置", nil)
        image:[UIImage systemImageNamed:@"gearshape.fill"] tag:4];

    self.viewControllers = @[play, library, controls, accounts, settings];
    self.tabBar.itemPositioning = UITabBarItemPositioningFill;
    self.tabBar.tintColor = [ModernUITheme accentColor];
    self.tabBar.accessibilityIdentifier = @"ModernLauncher.TabBar";

    // Keep the classic pre-iOS-26 tab-bar background and behavior. There are no
    // iOS 18/26 adaptive tab APIs here; UIKit receives the old, plain setup.
    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithDefaultBackground];
    if (@available(iOS 26.0, *)) {
        // UIKit owns the native Liquid Glass tab bar.
    } else {
        appearance.backgroundEffect = nil;
        appearance.backgroundColor = UIColor.systemBackgroundColor;
    }
    self.tabBar.standardAppearance = appearance;
    if (@available(iOS 15.0, *)) {
        self.tabBar.scrollEdgeAppearance = appearance;
    }
}

@end
