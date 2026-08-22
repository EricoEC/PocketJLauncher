#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

@interface FabricInstallViewController : PLPrefTableViewController
@property(nonatomic, copy) NSString *presetGameVersion;
@property(nonatomic, copy) NSString *presetVendor;
@property(nonatomic, copy) void (^installationDidFinish)(NSString *versionId);
@end
