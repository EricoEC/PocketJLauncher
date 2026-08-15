#import <UIKit/UIKit.h>

@interface AccountListViewController: UITableViewController<UIPopoverPresentationControllerDelegate>


@property (nonatomic, copy) void (^whenDelete)(NSString* name);
@property(nonatomic, copy) void (^whenItemSelected)();

+ (UIImage *)cachedAvatarForAccount:(NSDictionary *)account;
+ (void)loadBestAvatarForAccount:(NSDictionary *)account
                      completion:(void (^)(UIImage *avatar))completion;

@end
