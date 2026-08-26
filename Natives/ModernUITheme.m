#import "ModernUITheme.h"
#import "PocketJBackgroundManager.h"

@implementation ModernUITheme

+ (UIColor *)accentColor {
    return [UIColor colorWithRed:0.10 green:0.72 blue:0.35 alpha:1.0];
}

+ (BOOL)usesNativeLiquidGlass {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

+ (UIColor *)contentSurfaceBackgroundColor {
    if (@available(iOS 26.0, *)) return UIColor.clearColor;
    return UIColor.secondarySystemGroupedBackgroundColor;
}

+ (UINavigationBarAppearance *)navigationAppearance {
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    if (@available(iOS 26.0, *)) {
    } else {
        appearance.backgroundEffect = nil;
        appearance.backgroundColor = UIColor.systemBackgroundColor;
    }
    return appearance;
}

+ (void)applyGlobalAppearance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIColor *accent = [self accentColor];
        UINavigationBar *navigationBar = UINavigationBar.appearance;
        navigationBar.tintColor = accent;
        navigationBar.prefersLargeTitles = YES;

        // Leave iOS 26 navigation chrome untouched so UIKit can supply native
        // Liquid Glass. Earlier releases get their own stock material.
        if (@available(iOS 26.0, *)) {
            // Keep the system-provided Liquid Glass appearance.
        } else {
            UINavigationBarAppearance *navigation = [self navigationAppearance];
            navigationBar.standardAppearance = navigation;
            navigationBar.compactAppearance = navigation;
            navigationBar.scrollEdgeAppearance = navigation;
        }

        UISwitch.appearance.onTintColor = accent;
        UISlider.appearance.minimumTrackTintColor = accent;
        UIProgressView.appearance.progressTintColor = accent;
        UISearchBar.appearance.tintColor = accent;
    });
}

+ (void)styleController:(UIViewController *)controller {
    [PocketJBackgroundManager.shared applyToView:controller.view];
    controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAutomatic;
    controller.navigationController.navigationBar.prefersLargeTitles = YES;
    controller.navigationController.navigationBar.tintColor = self.accentColor;
}

+ (void)styleTableView:(UITableView *)tableView {
    tableView.backgroundColor = PocketJBackgroundManager.shared.enabled
        ? UIColor.clearColor : UIColor.systemGroupedBackgroundColor;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    tableView.estimatedRowHeight = 58.0;
    tableView.rowHeight = UITableViewAutomaticDimension;
}

+ (void)styleCell:(UITableViewCell *)cell destructive:(BOOL)destructive {
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = destructive ? UIColor.systemRedColor : UIColor.labelColor;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.tintColor = destructive ? UIColor.systemRedColor : self.accentColor;
}

+ (UIVisualEffectView *)glassViewWithCornerRadius:(CGFloat)cornerRadius interactive:(BOOL)interactive {
    UIVisualEffect *effect;
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.interactive = interactive;
        effect = glass;
    } else if (@available(iOS 15.0, *)) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    } else {
        // iOS 14 compatibility layer: the official visual-effect blur.
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
    if (![self usesNativeLiquidGlass]) {
        view.contentView.backgroundColor = [self contentSurfaceBackgroundColor];
    }
    view.layer.cornerRadius = cornerRadius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    return view;
}

+ (UIButtonConfiguration *)primaryButtonConfigurationWithTitle:(NSString *)title
                                                         image:(UIImage *)image API_AVAILABLE(ios(15.0)) {
    return [self actionButtonConfigurationWithTitle:title
                                             image:image
                                              tint:UIColor.systemGreenColor
                                         prominent:YES];
}

+ (UIButtonConfiguration *)actionButtonConfigurationWithTitle:(NSString *)title
                                                        image:(UIImage *)image
                                                         tint:(UIColor *)tint
                                                    prominent:(BOOL)prominent API_AVAILABLE(ios(15.0)) {
    UIButtonConfiguration *configuration;
    if (@available(iOS 26.0, *)) {
        configuration = prominent
            ? [UIButtonConfiguration prominentGlassButtonConfiguration]
            : [UIButtonConfiguration glassButtonConfiguration];
    } else if (prominent) {
        configuration = [UIButtonConfiguration filledButtonConfiguration];
    } else {
        configuration = [UIButtonConfiguration tintedButtonConfiguration];
    }
    configuration.title = title;
    configuration.image = image;
    configuration.imagePadding = prominent ? 9 : 7;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.baseForegroundColor =
        prominent ? UIColor.whiteColor : tint;
    configuration.baseBackgroundColor = tint;
    return configuration;
}

+ (void)styleContinuousButton:(UIButton *)button cornerRadius:(CGFloat)cornerRadius {
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.cornerRadius = cornerRadius;
    button.clipsToBounds = YES;
}

@end
