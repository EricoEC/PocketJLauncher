#import "SurfaceViewController.h"
#import "utils.h"

@implementation SurfaceViewController(LogView)

- (void)initCategory_LogView {
    self.logOutputView = [[PLLogOutputView alloc] initWithFrame:self.view.frame];
    self.logOutputView.navController.additionalSafeAreaInsets = self.view.safeAreaInsets;
    [self addChildViewController:self.logOutputView.navController];
    [self.rootView addSubview:self.logOutputView.navController.view];
}

@end
