#import <UIKit/UIKit.h>

@interface SurfaceView : UIView
- (void)displayLayer;
@end

@interface JavaGUIViewController : UIViewController
@property(nonatomic) NSString* filepath;
@property(nonatomic, readonly) int requiredJavaVersion;
@property(nonatomic) int requiredJavaVersionOverride;

- (void)setHitEnterAfterWindowShown:(BOOL)hitEnter;
@end
