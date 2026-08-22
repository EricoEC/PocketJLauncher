#import <UIKit/UIKit.h>

@interface ForgeInstallViewController : UITableViewController
@property(nonatomic, copy) NSString *presetGameVersion;
@property(nonatomic, copy) NSString *presetVendor;
@property(nonatomic, copy) NSString *targetInstanceName;
@property(nonatomic, copy) NSString *targetProfileName;
@end
