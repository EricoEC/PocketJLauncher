#import <UIKit/UIKit.h>

extern NSNotificationName const LauncherOpenModManagerNotification;

@interface LauncherProfilesViewController : UITableViewController

- (void)presentModManagerForInstanceNamed:(NSString *)instanceName;

@end
