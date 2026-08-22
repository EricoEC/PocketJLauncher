#import <UIKit/UIKit.h>

NSMutableArray<NSDictionary *> *localVersionList, *remoteVersionList;

FOUNDATION_EXPORT NSNotificationName const
    LauncherTaskStateDidChangeNotification;

@interface LauncherNavigationController : UINavigationController

@property(nonatomic) UIProgressView *progressViewMain, *progressViewSub;
@property(nonatomic) UILabel* progressText;

- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter;
- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter requiredJavaVersion:(int)requiredJavaVersion;
- (void)fetchLocalVersionList;
- (void)reloadProfileList;
- (void)setInteractionEnabled:(BOOL)enable forDownloading:(BOOL)downloading;
- (BOOL)hasActiveLaunchTask;
- (BOOL)isCurrentLaunchTaskPaused;
- (BOOL)selectedProfileNeedsDownload;
- (BOOL)selectedProfileHasInterruptedDownload;
- (void)pauseCurrentLaunchTask;
- (void)resumeCurrentLaunchTask;
- (void)cancelCurrentLaunchTask;
- (void)performInstallOrShowDetails:(id)sender;

@end
