#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ModernUITheme : NSObject
+ (UIColor *)accentColor;
+ (void)applyGlobalAppearance;
+ (void)styleController:(UIViewController *)controller;
+ (void)styleTableView:(UITableView *)tableView;
+ (void)styleCell:(UITableViewCell *)cell destructive:(BOOL)destructive;
+ (UIVisualEffectView *)glassViewWithCornerRadius:(CGFloat)cornerRadius interactive:(BOOL)interactive;
+ (UIButtonConfiguration *)primaryButtonConfigurationWithTitle:(NSString *)title
                                                         image:(UIImage *)image API_AVAILABLE(ios(15.0));
+ (UIButtonConfiguration *)actionButtonConfigurationWithTitle:(NSString *)title
                                                        image:(UIImage *)image
                                                         tint:(UIColor *)tint
                                                    prominent:(BOOL)prominent API_AVAILABLE(ios(15.0));
+ (void)styleContinuousButton:(UIButton *)button cornerRadius:(CGFloat)cornerRadius;
@end

NS_ASSUME_NONNULL_END
