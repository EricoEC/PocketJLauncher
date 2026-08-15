#import <UIKit/UIKit.h>

@interface PocketJBuildPlaceholderDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation PocketJBuildPlaceholderDelegate
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
            NSStringFromClass(PocketJBuildPlaceholderDelegate.class));
    }
}
